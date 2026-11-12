require "test_helper"

# A payment update mails the Jeevika Jankar the full payment details, but only
# when mail is switched on, and only to the test address while testing.
class JeevikaPaymentMailTest < ActionDispatch::IntegrationTest
  SLUG = "jeevika-jankar-payment-list-detail".freeze
  TEST_TO = "s.saxena@asabhopal.org".freeze

  FakeSms = Struct.new(:unused) do
    def deliver = PaymentAdviceSmsSender::Result.new(success: true, message: "ok")
  end

  setup do
    @saved_env = ENV.to_h.slice("PAYMENT_MAIL_TEST_TO", "PAYMENT_MAIL_ENABLED", "JJ_PAYMENT_MAIL_RELAY_URL")
    ENV.delete("PAYMENT_MAIL_TEST_TO")
    ENV.delete("PAYMENT_MAIL_ENABLED")
    ENV.delete("JJ_PAYMENT_MAIL_RELAY_URL")
    ActionMailer::Base.deliveries.clear
    PaymentAdviceSmsSender.define_singleton_method(:new) { |*_args, **_kwargs| FakeSms.new(nil) }

    tag = SecureRandom.hex(4)
    @vrp = Vrp.create!(
      name: "Mail JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: "9876500099",
      email: "realjj#{tag}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: "FCO-C Sausar"
    )
    @bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "bill_month" => "October", "financial_year" => "2026-2027", "select_vrp" => @vrp.id.to_s,
      "status" => "Final Approved", "final_approved_at" => "2026-10-29", "grand_total" => "2500.00"
    })
    admin = User.create!(user_name: "mail_admin_#{tag}", password: "secret", first_name: "Adm",
                         user_type: "admin", status: "Active")
    post login_path, params: { login: admin.user_name, password: "secret" }
  end

  teardown do
    PaymentAdviceSmsSender.singleton_class.send(:remove_method, :new)
    ENV.delete("PAYMENT_MAIL_TEST_TO")
    ENV.delete("PAYMENT_MAIL_ENABLED")
    ENV.delete("JJ_PAYMENT_MAIL_RELAY_URL")
    @saved_env.each { |key, value| ENV[key] = value }
    ModuleRecord.where(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG).each do |record|
      FileUtils.rm_f(Rails.root.join("public", record.data["excel_file"].to_s.delete_prefix("/"))) if record.data["excel_file"].present?
    end
  end

  # Swaps one class method for the block, and puts the real one back.
  def replacing(klass, name, replacement)
    original = klass.method(name)
    klass.define_singleton_method(name, &replacement)
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def pay!
    post payment_details_module_path(SLUG), params: { module_record: {
      payment_month: "October|2026-2027", selected_bill_ids: [@bill.id],
      transaction_id: "UTR778899", transaction_type: "NEFT", transaction_date: "2026-11-05"
    } }
  end

  test "no mail is sent unless mail is switched on" do
    pay!
    assert_empty ActionMailer::Base.deliveries
    assert_no_match(/Mail/, flash[:notice])
  end

  test "test mode sends every mail only to the test address, with full details" do
    ENV["PAYMENT_MAIL_TEST_TO"] = TEST_TO
    pay!

    assert_equal 1, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.last
    assert_equal [TEST_TO], mail.to
    assert_match "[TEST]", mail.subject
    body = mail.text_part.body.to_s
    ["Mail JJ", "UTR778899", "NEFT", "05/11/2026", "29/10/2026", "2500.00", "October", "2026-2027", @vrp.email].each do |text|
      assert_includes body, text
    end
    assert_includes mail.html_part.body.to_s, "UTR778899"
    assert_match "Mail sent: 1.", flash[:notice]
  end

  test "enabled mode sends to the Jeevika Jankar's own email" do
    ENV["PAYMENT_MAIL_ENABLED"] = "true"
    pay!
    assert_equal [@vrp.email], ActionMailer::Base.deliveries.last.to
    assert_no_match "[TEST]", ActionMailer::Base.deliveries.last.subject
  end

  test "excel upload mails each updated bill too" do
    ENV["PAYMENT_MAIL_TEST_TO"] = TEST_TO
    csv = CSV.generate do |rows|
      rows << ["Bill ID", "Transaction ID", "Transaction Type", "Transaction Date"]
      rows << [@bill.id, "UTRX1", "IMPS", "06/11/2026"]
    end
    file = Tempfile.new(["upload", ".csv"])
    file.write(csv)
    file.rewind
    post payment_details_upload_module_path(SLUG), params: { payment_excel_file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "p.csv") }

    assert_equal [TEST_TO], ActionMailer::Base.deliveries.last.to
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "UTRX1"
    assert_match "Mail sent: 1.", flash[:notice]
  end

  test "a mail failure does not undo the saved payment" do
    ENV["PAYMENT_MAIL_TEST_TO"] = TEST_TO
    JeevikaPaymentMailer.define_singleton_method(:payment_updated) { |*_args| raise Net::SMTPAuthenticationError, "535 bad login" }
    assert_difference -> { ModuleRecord.where(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG).count }, 1 do
      pay!
    end
    assert_match "Mail failed: 1.", flash[:notice]
  ensure
    JeevikaPaymentMailer.singleton_class.send(:remove_method, :payment_updated)
  end

  test "with the krai relay set the mail goes through krai, not SMTP" do
    ENV["PAYMENT_MAIL_TEST_TO"] = TEST_TO
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    sent = []
    relay = ->(recipient, details, test_mode:) { sent << [recipient, details, test_mode] }
    replacing(JeevikaPaymentMailRelay, :deliver!, relay) { pay! }

    assert_empty ActionMailer::Base.deliveries
    recipient, details, test_mode = sent.sole
    assert_equal TEST_TO, recipient
    assert test_mode
    assert_equal "UTR778899", details[:transaction_id]
    assert_equal @vrp.email, details[:jj_email]
    assert_match "Mail sent: 1.", flash[:notice]
  end

  test "a krai failure does not undo the saved payment" do
    ENV["PAYMENT_MAIL_ENABLED"] = "true"
    ENV["JJ_PAYMENT_MAIL_RELAY_URL"] = "https://krai.asaindia.org/"
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    response.instance_variable_set(:@read, true)
    response.body = "boom"
    assert_difference -> { ModuleRecord.where(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG).count }, 1 do
      replacing(JeevikaPaymentMailRelay, :get, ->(_uri) { response }) { pay! }
    end
    assert_match "Mail failed: 1.", flash[:notice]
  end
end
