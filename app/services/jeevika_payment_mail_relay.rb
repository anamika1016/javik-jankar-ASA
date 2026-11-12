require "json"
require "net/http"
require "uri"

# Sends the Jeevika Jankar payment update mail through the ASA mail service
# (krai) from its notification mailbox, the same way Apurti (Asset Management)
# sends its mails, because this server has no working SMTP. The app calls one
# krai page with the payment details as query parameters; krai builds the mail
# in its own format and sends it.
#
#   GET https://krai.asaindia.org/jj_payment_notify.aspx?to_email=...&to_name=...&subject=...&...
#
# JJ_PAYMENT_MAIL_RELAY_URL is krai's address (https://krai.asaindia.org/) or
# the full page address (…/x.aspx). Off until it is set; the SMTP mailer is
# used then. Who receives the mail is still decided by
# JeevikaPaymentMailer.recipient_for (PAYMENT_MAIL_TEST_TO / PAYMENT_MAIL_ENABLED).
#
# A 2xx answer is a success unless its JSON says otherwise
# ("success": false, or "status": "error"/"failed"), or krai's page says it
# sent nothing ("no email was sent").
#
# krai's test_mode=1 means "show a preview, send nothing", so it is always 0:
# a mail to the PAYMENT_MAIL_TEST_TO address is a real mail, marked [TEST]
# in its subject and carrying the JJ's own address in actual_email.
class JeevikaPaymentMailRelay
  class DeliveryError < StandardError; end

  DEFAULT_PAGE = "jj_payment_notify.aspx".freeze
  TIMEOUT_SECONDS = 15
  MAX_REDIRECTS = 3
  NOT_SENT = /no e-?mail was sent/i

  # Every parameter krai receives, in this order.
  FIELDS = %w[
    to_email to_name subject message
    jj_id name mobile_no financial_year bill_month bill_id approval_date amount
    transaction_id transaction_type transaction_date updated_on updated_by
    test_mode actual_email
  ].freeze

  def self.enabled?
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"].to_s.strip.present?
  end

  # A bare host (https://krai.asaindia.org/) points at the default page.
  def self.url
    uri = URI.parse(ENV["JJ_PAYMENT_MAIL_RELAY_URL"].to_s.strip)
    return uri.to_s if uri.path.to_s.end_with?(".aspx")

    URI.join(uri.to_s.end_with?("/") ? uri.to_s : "#{uri}/", DEFAULT_PAGE).to_s
  end

  # details: hash built by ModulesController#jeevika_payment_mail_details
  def self.params_for(recipient, details, test_mode: false)
    subject = JeevikaPaymentMailer::SUBJECT
    subject = "[TEST] #{subject} (#{details[:name]})" if test_mode
    {
      "to_email" => recipient,
      "to_name" => details[:name],
      "subject" => subject,
      "message" => "#{details[:bill_month]} #{details[:financial_year]} ke bill ki Rs. #{details[:amount]} payment " \
                   "#{details[:transaction_date_label]} ko #{details[:transaction_type]} dwara bhej di gayi hai.",
      "jj_id" => details[:jj_id],
      "name" => details[:name],
      "mobile_no" => details[:mobile_no],
      "financial_year" => details[:financial_year],
      "bill_month" => details[:bill_month],
      "bill_id" => details[:bill_id],
      "approval_date" => details[:approval_date_label],
      "amount" => details[:amount],
      "transaction_id" => details[:transaction_id],
      "transaction_type" => details[:transaction_type],
      "transaction_date" => details[:transaction_date_label],
      "updated_on" => details[:updated_at_label],
      "updated_by" => details[:updated_by],
      "test_mode" => "0",
      "actual_email" => test_mode ? details[:jj_email] : ""
    }.transform_values(&:to_s)
  end

  def self.request_uri(recipient, details, test_mode: false)
    uri = URI.parse(url)
    uri.query = URI.encode_www_form(params_for(recipient, details, test_mode: test_mode))
    uri
  end

  def self.deliver!(recipient, details, test_mode: false)
    response, final_uri = fetch(request_uri(recipient, details, test_mode: test_mode))
    # The address (without the payment details) helps to see where it went.
    where = "[#{final_uri.scheme}://#{final_uri.host}#{final_uri.path}]"
    raise DeliveryError, "Mail service asked for a login #{where}" if login_page?(final_uri)
    raise DeliveryError, "#{failure_message(response)} #{where}" unless success?(response)

    Rails.logger.info("JeevikaPaymentMailRelay sent bill=#{details[:bill_id]} to=#{recipient} status=#{response.code} #{where}")
    true
  rescue DeliveryError
    raise
  rescue StandardError => error
    raise DeliveryError, "Mail service could not be reached (#{error.class}: #{error.message})."
  end

  # krai's page may answer with a redirect (302 "Object moved") to a result
  # page; follow it and judge the page it ends on.
  def self.fetch(uri)
    response = get(uri)
    MAX_REDIRECTS.times do
      break unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = URI.join(uri.to_s, response["location"])
      response = get(uri)
    end
    [response, uri]
  end

  def self.get(uri)
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept"] = "application/json"

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(request)
    end
  end

  def self.login_page?(uri)
    uri.path.to_s.downcase.match?(/login|signin|sign_in/)
  end

  def self.success?(response)
    return false unless response.is_a?(Net::HTTPSuccess)
    return false if response.body.to_s.match?(NOT_SENT)

    body = parsed_body(response)
    return true unless body.is_a?(Hash)
    return false if body.key?("success") && !ActiveModel::Type::Boolean.new.cast(body["success"])

    !body["status"].to_s.downcase.in?(%w[error failed failure])
  end

  def self.failure_message(response)
    body = parsed_body(response)
    detail = body["message"] || body["error"] if body.is_a?(Hash)
    detail ||= "krai sent no email (#{response.body.to_s[NOT_SENT]})" if response.body.to_s.match?(NOT_SENT)
    detail ||= response.body.to_s.gsub(/<[^>]+>/, " ").squish.first(160)
    "Mail service returned #{response.code}: #{detail.presence || response.message}"
  end

  def self.parsed_body(response)
    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    nil
  end
end
