require "net/http"
require "uri"
require "json"
require "digest"

# Reads a farmer out of the ASA register by mobile or Aadhaar. Shared by the
# Farmer 360 web page and the Android login API so both see the same record.
# Read-only -- this never writes to the register.
#
# Every call here is a round trip to another server, so a farmer logging in
# would otherwise wait for it twice: once to send the OTP and again to verify
# it. The answer is cached for a few minutes, which makes verify a cache hit
# and returns the app a token immediately.
class FarmerRegisterLookup
  ENDPOINT = "https://asa.ploughmanagro.com/api/farmer_details_by_identifier".freeze
  # The register normally answers in well under a second. A long wait here is
  # the register being unreachable, and the app is better told that quickly
  # than left on a spinner.
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 8
  CACHE_TTL = 5.minutes
  # A farmer who is not in the register will not appear a second later either;
  # remembering the miss briefly stops a retrying app from hammering it.
  MISS_CACHE_TTL = 30.seconds

  Result = Struct.new(:farmer, :error, keyword_init: true) do
    def found?
      farmer.present?
    end
  end

  def self.by_mobile(mobile_no, refresh: false)
    new(mobile_no: mobile_no).call(refresh: refresh)
  end

  def self.by_aadhaar(aadhaar_no, refresh: false)
    new(aadhaar_no: aadhaar_no).call(refresh: refresh)
  end

  def initialize(mobile_no: nil, aadhaar_no: nil)
    @mobile_no = mobile_no.to_s.gsub(/\D/, "")
    @aadhaar_no = aadhaar_no.to_s.gsub(/\D/, "")
  end

  def call(refresh: false)
    return Result.new(error: "Mobile number or Aadhaar number is required.") if query_params.blank?

    Rails.cache.delete(cache_key) if refresh
    cached = Rails.cache.read(cache_key)
    return Result.new(**cached) if cached.is_a?(Hash)

    result = fetch
    # Transport failures are not cached: the next attempt should really retry.
    if result.found?
      Rails.cache.write(cache_key, { farmer: result.farmer }, expires_in: CACHE_TTL)
    elsif result.error == "Farmer Not Found"
      Rails.cache.write(cache_key, { error: result.error }, expires_in: MISS_CACHE_TTL)
    end
    result
  end

  private

  attr_reader :mobile_no, :aadhaar_no

  def fetch
    response = get(uri)
    unless response.is_a?(Net::HTTPSuccess)
      return Result.new(error: "Farmer register is not responding right now.")
    end

    payload = JSON.parse(response.body)
    farmer = payload["result"]
    if payload["status"] == false || farmer.blank?
      return Result.new(error: payload["message"].presence || "Farmer Not Found")
    end

    Result.new(farmer: farmer)
  rescue StandardError => error
    # The identifier is not logged: it is an Aadhaar or a personal mobile.
    Rails.logger.warn("Farmer register lookup failed: #{error.class} - #{error.message}")
    Result.new(error: "Farmer register is not reachable right now.")
  end

  # The identifier is hashed rather than placed in the key, so an Aadhaar
  # never lands in the cache store or in a cache-key log line.
  def cache_key
    kind, value = query_params.first
    ["farmer-register-lookup-v1", kind, Digest::SHA256.hexdigest("#{kind}:#{value}")].join(":")
  end

  def query_params
    return { mobile_no: mobile_no } if mobile_no.present?
    return { aadhaar_no: aadhaar_no } if aadhaar_no.present?

    {}
  end

  def uri
    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form(query_params)
    uri
  end

  def get(uri)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
  end
end
