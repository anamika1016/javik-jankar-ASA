require "test_helper"

class JeevikaPaymentMailRelayTest < ActiveSupport::TestCase
  DETAILS = {
    bill_id: "41", jj_id: "7", jj_email: "jj@example.com", name: "Ram Kumar", mobile_no: "9876500099",
    financial_year: "2026-2027", bill_month: "October", approval_date_label: "29/10/2026", amount: "2500.00",
    transaction_id: "UTR778899", transaction_type: "NEFT", transaction_date_label: "05/11/2026",
    updated_at_label: "05/11/2026 11:30 AM", updated_by: "Admin"
  }.freeze

  setup do
    @saved_url = ENV["JJ_PAYMENT_MAIL_RELAY_URL"]
  end

  teardown do
    @saved_url.nil? ? ENV.delete("JJ_PAYMENT_MAIL_RELAY_URL") : ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = @saved_url
  end

  test "off until the krai address is set" do
    ENV.delete("JJ_PAYMENT_MAIL_RELAY_URL")
    refute JeevikaPaymentMailRelay.enabled?
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    assert JeevikaPaymentMailRelay.enabled?
  end

  test "a bare krai host points at the default page; a full page is kept" do
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org"
    assert_equal "https://krai.asaindia.org/jj_payment_notify.aspx", JeevikaPaymentMailRelay.url
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/other.aspx"
    assert_equal "https://krai.asaindia.org/other.aspx", JeevikaPaymentMailRelay.url
  end

  test "sends every field krai needs" do
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    query = URI.decode_www_form(JeevikaPaymentMailRelay.request_uri("jj@example.com", DETAILS).query).to_h

    assert_equal JeevikaPaymentMailRelay::FIELDS, query.keys
    assert_equal "jj@example.com", query["to_email"]
    assert_equal "Jeevika Jankar Payment Notification", query["subject"]
    assert_equal "UTR778899", query["transaction_id"]
    assert_equal "0", query["test_mode"]
    assert_equal "", query["actual_email"]
  end

  test "test mode marks the subject and carries the real address, but still sends" do
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    query = JeevikaPaymentMailRelay.params_for("tester@asabhopal.org", DETAILS, test_mode: true)
    assert_match "[TEST]", query["subject"]
    # krai's test_mode=1 is a preview that sends nothing.
    assert_equal "0", query["test_mode"]
    assert_equal "jj@example.com", query["actual_email"]
  end

  test "a JSON failure from krai is a failed mail" do
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = '{"success":false,"message":"Invalid email"}'
    stub_get(response) do
      error = assert_raises(JeevikaPaymentMailRelay::DeliveryError) { JeevikaPaymentMailRelay.deliver!("jj@example.com", DETAILS) }
      assert_match "Invalid email", error.message
    end
  end

  test "a 200 answer is a sent mail" do
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = "Mail sent"
    stub_get(response) { assert JeevikaPaymentMailRelay.deliver!("jj@example.com", DETAILS) }
  end

  test "a krai preview page that sent nothing is a failed mail" do
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = "<div class='info'>Test mode is ON. Notification preview generated; no email was sent.</div>"
    stub_get(response) do
      error = assert_raises(JeevikaPaymentMailRelay::DeliveryError) { JeevikaPaymentMailRelay.deliver!("jj@example.com", DETAILS) }
      assert_match "no email was sent", error.message
    end
  end

  private

  def stub_get(response)
    original = JeevikaPaymentMailRelay.method(:get)
    JeevikaPaymentMailRelay.define_singleton_method(:get) { |_uri| response }
    yield
  ensure
    JeevikaPaymentMailRelay.define_singleton_method(:get, original)
  end
end
