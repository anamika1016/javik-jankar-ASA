require "net/http"
require "uri"
require "json"

class PaymentAdviceSmsSender
  DEFAULT_API_URL = "https://sms.yoursmsbox.com/api/sendhttp.php".freeze
  DEFAULT_TIMEOUT_SECONDS = 10

  AUTH_KEY = "37317061706c39353312".freeze
  SENDER = "PLOAPL".freeze
  TEMPLATE_ID = "1707175758077109741".freeze
  MESSAGE_TEMPLATE =
    "Payment Advice Notification:- Your NEFT Txn. with Ref. No. %<reference_number>s for Rs. %<amount>s has been credited to beneficiary : %<beneficiary_name>s on %<transaction_date>s . Ploughman Agro Private Limited".freeze

  Result = Struct.new(:success, :message, :response_code, :response_body, keyword_init: true) do
    def success?
      success
    end
  end

  attr_reader :mobile_number, :reference_number, :amount, :beneficiary_name, :transaction_date

  def initialize(mobile_number, reference_number:, amount:, beneficiary_name:, transaction_date:)
    @mobile_number = mobile_number.to_s
    @reference_number = reference_number.to_s.strip
    @amount = format_amount(amount)
    @beneficiary_name = beneficiary_name.to_s.strip
    @transaction_date = format_transaction_date(transaction_date)
  end

  def deliver
    if auth_key.blank?
      Rails.logger.warn("[Payment SMS] SMS auth key is not configured; payment advice was not sent.")
      return Result.new(success: false, message: "SMS auth key is not configured.")
    end

    if provider_mobile_number.blank?
      return Result.new(success: false, message: "Mobile number is missing.")
    end

    if [reference_number, amount, beneficiary_name, transaction_date].any?(&:blank?)
      return Result.new(success: false, message: "Payment SMS details are incomplete.")
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
    Rails.logger.error("[Payment SMS] Gateway error: #{e.class} #{e.message}")
    Result.new(success: false, message: "#{e.class}: #{e.message}")
  end

  def sms_api_url
    ENV["SMS_API_URL"].presence || DEFAULT_API_URL
  end

  def auth_key
    ENV["SMS_PAYMENT_AUTH_KEY"].presence || AUTH_KEY
  end

  def request_with_redirects(uri, limit = 3)
    raise "SMS gateway redirected too many times." if limit.zero?

    response = http_get(uri)
    if response.is_a?(Net::HTTPRedirection)
      redirect_uri = URI.parse(response["location"].to_s)
      redirect_uri = uri.merge(response["location"].to_s) if redirect_uri.relative?
      Rails.logger.info("[Payment SMS] Gateway redirected to #{redirect_uri}")
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

  def timeout_seconds
    seconds = ENV.fetch("SMS_API_TIMEOUT", DEFAULT_TIMEOUT_SECONDS).to_i
    seconds.positive? ? seconds : DEFAULT_TIMEOUT_SECONDS
  end

  def payload
    {
      authkey: auth_key,
      mobiles: provider_mobile_number,
      message: message,
      sender: SENDER,
      route: 2,
      country: 0,
      DLT_TE_ID: TEMPLATE_ID,
      response: "json"
    }
  end

  def provider_mobile_number
    digits = mobile_number.gsub(/\D/, "")
    return "91#{digits}" if digits.match?(/\A[6-9]\d{9}\z/)
    return digits if digits.match?(/\A91[6-9]\d{9}\z/)

    digits
  end

  def message
    format(
      MESSAGE_TEMPLATE,
      reference_number: reference_number,
      amount: amount,
      beneficiary_name: beneficiary_name,
      transaction_date: transaction_date
    )
  end

  def format_amount(value)
    number = BigDecimal(value.to_s)
    number == number.to_i ? number.to_i.to_s : format("%.2f", number)
  rescue ArgumentError
    value.to_s.strip
  end

  def format_transaction_date(value)
    date =
      case value
      when Date then value
      when Time, ActiveSupport::TimeWithZone, DateTime then value.to_date
      else
        Date.parse(value.to_s)
      end

    date.strftime("%B #{date.day}, %Y")
  rescue ArgumentError, TypeError
    value.to_s.strip
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
    return parsed["Description"].presence || "Gateway accepted payment SMS request." if success

    parsed["Description"].presence ||
      parsed["message"].presence ||
      "Gateway returned #{response.code}."
  end

  def log_gateway_response(response, success, parsed)
    log_message = "[Payment SMS] Gateway response: #{response.code} #{response.body} parsed=#{parsed.inspect}"
    success ? Rails.logger.info(log_message) : Rails.logger.warn(log_message)
  end
end
