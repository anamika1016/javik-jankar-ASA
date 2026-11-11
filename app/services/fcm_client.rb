require "net/http"
require "uri"
require "json"
require "openssl"
require "base64"

# Firebase Cloud Messaging, HTTP v1.
#
# The old /fcm/send endpoint with a server key was shut down by Google in
# 2024, so this uses the v1 API, which needs an OAuth token signed with the
# project's service account. The JWT is assembled with OpenSSL rather than
# pulling in googleauth for one signature.
#
# Credentials come from FCM_SERVICE_ACCOUNT_JSON (the whole service-account
# JSON) or Rails credentials under :fcm. With neither, sending reports
# "not configured" instead of raising -- publishing a news item must not fail
# because push is not set up yet.
class FcmClient
  TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
  SCOPE = "https://www.googleapis.com/auth/firebase.messaging".freeze
  # FCM v1 sends to one token per call; this caps a broadcast so one slow
  # batch cannot hold a worker forever.
  MAX_TOKENS = 2_000
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 10

  Result = Struct.new(:sent, :failed, :dead_tokens, :error, keyword_init: true) do
    def configured? = error != :not_configured
    def ok? = error.nil?
  end

  class << self
    def configured?
      credentials.present?
    end

    # Returns a Result. Tokens FCM reports as dead come back so the caller can
    # delete them; a phone that uninstalled the app would otherwise be retried
    # on every broadcast forever.
    def send_notification(tokens:, title:, body:, data: {})
      tokens = Array(tokens).compact_blank.uniq.first(MAX_TOKENS)
      return Result.new(sent: 0, failed: 0, dead_tokens: [], error: :no_tokens) if tokens.empty?
      return Result.new(sent: 0, failed: 0, dead_tokens: [], error: :not_configured) unless configured?

      access_token = fetch_access_token
      return Result.new(sent: 0, failed: 0, dead_tokens: [], error: :auth_failed) if access_token.blank?

      sent = 0
      failed = 0
      dead = []
      tokens.each do |token|
        status, payload = post_message(access_token, token, title, body, data)
        if status == 200
          sent += 1
        else
          failed += 1
          dead << token if token_dead?(status, payload)
        end
      end

      Result.new(sent: sent, failed: failed, dead_tokens: dead)
    rescue StandardError => error
      Rails.logger.error("FCM send failed: #{error.class} - #{error.message}")
      Result.new(sent: 0, failed: Array(tokens).size, dead_tokens: [], error: :exception)
    end

    private

    def credentials
      return @credentials if defined?(@credentials) && @credentials

      raw = ENV["FCM_SERVICE_ACCOUNT_JSON"].presence
      parsed = raw ? (JSON.parse(raw) rescue nil) : nil
      parsed ||= Rails.application.credentials.fcm&.deep_stringify_keys
      @credentials = parsed if parsed && parsed["private_key"].present? && parsed["client_email"].present?
    end

    def project_id
      ENV["FCM_PROJECT_ID"].presence || credentials&.dig("project_id")
    end

    # Google's tokens last an hour; re-signing one per notification would add
    # a round trip to every single message.
    def fetch_access_token
      Rails.cache.fetch("fcm-access-token", expires_in: 50.minutes) { request_access_token }
    rescue StandardError
      request_access_token
    end

    def request_access_token
      now = Time.current.to_i
      claim = {
        "iss" => credentials["client_email"], "scope" => SCOPE,
        "aud" => TOKEN_URL, "iat" => now, "exp" => now + 3600
      }
      assertion = signed_jwt(claim)

      response = post_form(URI(TOKEN_URL), {
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion" => assertion
      })
      return unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)["access_token"]
    rescue StandardError => error
      Rails.logger.error("FCM auth failed: #{error.class} - #{error.message}")
      nil
    end

    def signed_jwt(claim)
      segments = [{ "alg" => "RS256", "typ" => "JWT" }, claim].map { |part| base64url(JSON.dump(part)) }
      key = OpenSSL::PKey::RSA.new(credentials["private_key"])
      signature = key.sign(OpenSSL::Digest::SHA256.new, segments.join("."))
      (segments << base64url(signature)).join(".")
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end

    def post_message(access_token, token, title, body, data)
      uri = URI("https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send")
      payload = {
        message: {
          token: token,
          notification: { title: title.to_s, body: body.to_s },
          # Every value in an FCM data block has to be a string.
          data: data.transform_keys(&:to_s).transform_values(&:to_s),
          android: { priority: "high", notification: { sound: "default" } }
        }
      }

      response = post_json(uri, payload, "Authorization" => "Bearer #{access_token}")
      [response.code.to_i, (JSON.parse(response.body) rescue {})]
    end

    # UNREGISTERED / INVALID_ARGUMENT means this token will never work again.
    def token_dead?(status, payload)
      return true if status == 404

      reason = payload.dig("error", "details")&.find { |d| d["errorCode"] }&.dig("errorCode").to_s
      status == 400 && reason == "INVALID_ARGUMENT" || reason == "UNREGISTERED"
    end

    def post_json(uri, payload, headers = {})
      request = Net::HTTP::Post.new(uri.request_uri, headers.merge("Content-Type" => "application/json"))
      request.body = JSON.dump(payload)
      perform(uri, request)
    end

    def post_form(uri, form)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data(form)
      perform(uri, request)
    end

    def perform(uri, request)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) }
    end
  end
end
