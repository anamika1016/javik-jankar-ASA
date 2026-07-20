require "net/http"
require "uri"
require "json"

class OtpSmsSender
  DEFAULT_API_URL = "https://sms.yoursmsbox.com/api/sendhttp.php".freeze
  DEFAULT_TIMEOUT_SECONDS = 10

  # ASA / ACTFSA account (login OTP) — matches SmsOtpService credentials.
  ASA_AUTH_KEY = "3230666f72736131353261".freeze
  ASA_SENDER = "ACTFSA".freeze
  ASA_TEMPLATE_ID = "1707174348305252031".freeze
  ASA_MESSAGE_TEMPLATE = "Action For Social Advancement (ASA)-Login OTP: %<otp>s".freeze

  # PAPL account (forgot-password OTP on web).
  PAPL_AUTH_KEY = "37317061706c39353312".freeze
  PAPL_SENDER = "PLOAPL".freeze
  PAPL_TEMPLATE_ID = "1707178065575161459".freeze

  TEMPLATES = {
    forgot_password: {
      auth_key: ASA_AUTH_KEY,
      template_id: ASA_TEMPLATE_ID,
      sender: ASA_SENDER,
      unicode: true,
      message: ->(otp) { format(ASA_MESSAGE_TEMPLATE, otp: otp) }
    },
    login: {
      auth_key: ASA_AUTH_KEY,
      template_id: ASA_TEMPLATE_ID,
      sender: ASA_SENDER,
      unicode: true,
      message: ->(otp) { format(ASA_MESSAGE_TEMPLATE, otp: otp) }
    }
  }.freeze

  Result = Struct.new(:success, :message, :response_code, :response_body, keyword_init: true) do
    def success?
      success
    end
  end

  attr_reader :mobile_number, :otp, :purpose

  def initialize(mobile_number, otp, purpose: :forgot_password)
    @mobile_number = mobile_number.to_s
    @otp = otp.to_s
    @purpose = purpose.to_sym
  end

  def deliver
    if sms_auth_key.blank?
      Rails.logger.warn("[OTP SMS] SMS auth key is not configured; OTP was not sent.")
      return Result.new(success: false, message: "SMS auth key is not configured.")
    end

    deliver_to_gateway
  end

  private

  def deliver_to_gateway
    uri = URI.parse(sms_api_url)
    existing_query = uri.query.present? ? URI.decode_www_form(uri.query).to_h : {}
    uri.query = URI.encode_www_form(existing_query.merge(payload))

    response = request_with_redirects(uri)
    parsed = parse_gateway_body(response.body)
    success = gateway_accepted?(response, parsed)
    log_gateway_response(response, success, parsed)

    Result.new(
      success: success,
      message: gateway_result_message(success, response, parsed),
      response_code: response.code,
      response_body: response.body
    )
  rescue StandardError => e
    Rails.logger.error("[OTP SMS] Gateway error: #{e.class} #{e.message}")
    Result.new(success: false, message: "#{e.class}: #{e.message}")
  end

  def sms_api_url
    ENV["SMS_API_URL"].presence || DEFAULT_API_URL
  end

  def request_with_redirects(uri, limit = 3)
    raise "SMS gateway redirected too many times." if limit.zero?

    response = http_get(uri)
    if response.is_a?(Net::HTTPRedirection)
      redirect_uri = URI.parse(response["location"].to_s)
      redirect_uri = uri.merge(response["location"].to_s) if redirect_uri.relative?
      Rails.logger.info("[OTP SMS] Gateway redirected to #{redirect_uri}")
      return request_with_redirects(redirect_uri, limit - 1)
    end

    response
  end

  def http_get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds

    http.request(Net::HTTP::Get.new(uri.request_uri))
  end

  def sms_auth_key
    env_key = purpose == :login ? ENV["SMS_LOGIN_AUTH_KEY"] : ENV["SMS_AUTH_KEY"]
    env_key.presence || template_config[:auth_key]
  end

  def timeout_seconds
    seconds = ENV.fetch("SMS_API_TIMEOUT", DEFAULT_TIMEOUT_SECONDS).to_i
    seconds.positive? ? seconds : DEFAULT_TIMEOUT_SECONDS
  end

  def log_gateway_response(response, success, parsed)
    log_message = "[OTP SMS] Gateway response: #{response.code} #{response.body} parsed=#{parsed.inspect}"
    success ? Rails.logger.info(log_message) : Rails.logger.warn(log_message)
  end

  def template_config
    TEMPLATES[purpose] || TEMPLATES[:forgot_password]
  end

  def payload
    data = {
      authkey: sms_auth_key,
      mobiles: provider_mobile_number,
      message: message,
      sender: template_config[:sender].to_s,
      route: 2,
      country: 0,
      DLT_TE_ID: template_config[:template_id].to_s,
      response: "json"
    }
    data[:unicode] = 1 if template_config[:unicode]
    data
  end

  def provider_mobile_number
    digits = mobile_number.gsub(/\D/, "")
    return "91#{digits}" if digits.match?(/\A[6-9]\d{9}\z/)
    return digits if digits.match?(/\A91[6-9]\d{9}\z/)

    digits
  end

  def message
    template_config[:message].call(otp)
  end

  def parse_gateway_body(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  def gateway_accepted?(response, parsed)
    return false unless response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s.strip
    return true if body.match?(/\A\d+\z/)

    status = parsed["Status"].to_s
    code = parsed["Code"].to_s
    return true if status.casecmp("Success").zero? || code == "000"
    return true if body.downcase.include?("success")
    return false if status.present? || code.present?

    body.present? && !body.match?(/fail|error|invalid/i)
  end

  def gateway_result_message(success, response, parsed)
    return parsed["Description"].presence || "Gateway accepted OTP request." if success

    parsed["Description"].presence ||
      parsed["message"].presence ||
      "Gateway returned #{response.code}."
  end
end
