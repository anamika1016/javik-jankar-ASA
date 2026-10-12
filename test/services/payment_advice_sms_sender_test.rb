require "test_helper"

class PaymentAdviceSmsSenderTest < ActiveSupport::TestCase
  test "payment SMS uses the ASA header template and exact approved wording" do
    sender = build_sender
    payload = sender.send(:payload)
    assert_equal "ACTFSA", payload[:sender]
    assert_equal "1777179179837744556", payload[:DLT_TE_ID]
    assert_equal "919876543210", payload[:mobiles]
    assert_equal "Payment Advice Notification:- Your NEFT Txn. with Ref. No. AXSK252320020788 for Rs. 1600 has been credited to beneficiary : Sharad Saxena on August 20, 2025 . Action for social advancement(ASA)", payload[:message]
    refute_includes payload[:message], "Ploughman"
    assert_equal OtpSmsSender::ASA_AUTH_KEY, PaymentAdviceSmsSender::AUTH_KEY
  end

  test "delivery sends the approved payload and handles gateway acceptance without a real SMS" do
    sender = build_sender
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = '{"Status":"Success","Code":"000"}'
    captured = nil
    sender.define_singleton_method(:http_get) do |uri|
      captured = URI.decode_www_form(uri.query).to_h
      response
    end
    assert sender.deliver.success?
    assert_equal "ACTFSA", captured["sender"]
    assert_equal "1777179179837744556", captured["DLT_TE_ID"]
    assert_includes captured["message"], "Action for social advancement(ASA)"
  end

  test "gateway rejection is returned as a failed SMS" do
    sender = build_sender
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    response.instance_variable_set(:@read, true)
    response.body = '{"Status":"Error","Description":"Template rejected"}'
    sender.define_singleton_method(:http_get) { |*| response }
    result = sender.deliver
    refute result.success?
    assert_equal "Template rejected", result.message
  end

  test "missing payment details skip gateway requests and decimal amounts keep their formatting" do
    sender = build_sender(reference_number: "", amount: "1600.50")
    assert_equal "1600.50", sender.amount
    called = false
    sender.define_singleton_method(:http_get) { |*| called = true }
    refute sender.deliver.success?
    refute called, "Incomplete details must not call the gateway"
  end

  private

  def build_sender(reference_number: "AXSK252320020788", amount: "1600")
    PaymentAdviceSmsSender.new("9876543210", reference_number: reference_number,
      amount: amount, beneficiary_name: "Sharad Saxena", transaction_date: Date.new(2025, 8, 20))
  end
end
