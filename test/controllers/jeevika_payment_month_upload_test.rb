require "test_helper"

# Payment List Detail works month wise, splits bills into Updated / Not Updated
# tabs and accepts the payment details for many bills from one Excel sheet.
class JeevikaPaymentMonthUploadTest < ActionDispatch::IntegrationTest
  SLUG = "jeevika-jankar-payment-list-detail".freeze

  FakeSms = Struct.new(:calls) do
    def deliver
      calls << 1
      PaymentAdviceSmsSender::Result.new(success: true, message: "ok")
    end
  end

  setup do
    @tag = SecureRandom.hex(4)
    @vrp = Vrp.create!(
      name: "Pay JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: "9876500088",
      email: "pay#{@tag}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: "FCO-C Sausar"
    )
    @oct_a = bill("October", "2026-10-29")
    @oct_b = bill("October", "2026-10-28")
    @sep = bill("September", "2026-10-20")

    @admin = User.create!(user_name: "pay_admin_#{@tag}", password: "secret", first_name: "Adm",
                          user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
    @sms_calls = []
  end

  # Uploads are written to public/uploads; remove the ones these tests stored.
  teardown do
    payments.filter_map { |record| record.data["excel_file"].presence }.each do |url|
      FileUtils.rm_f(Rails.root.join("public", url.delete_prefix("/")))
    end
  end

  def bill(month, approved_on, year: "2026-2027")
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "bill_month" => month, "financial_year" => year, "select_vrp" => @vrp.id.to_s,
      "status" => "Final Approved", "final_approved_at" => approved_on, "grand_total" => "1500.00"
    })
  end

  # Never reach the real SMS gateway from a test.
  def with_fake_sms
    calls = @sms_calls
    PaymentAdviceSmsSender.define_singleton_method(:new) { |*_args, **_kwargs| FakeSms.new(calls) }
    yield
  ensure
    # Dropping the singleton override restores the normal Class#new.
    PaymentAdviceSmsSender.singleton_class.send(:remove_method, :new)
  end

  def payments
    ModuleRecord.where(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG)
  end

  def upload_file(headers, rows, ext: ".xlsx")
    content = if ext == ".csv"
      CSV.generate { |csv| ([headers] + rows).each { |row| csv << row } }
    else
      XlsxExporter.generate(headers: headers, rows: rows)
    end
    file = Tempfile.new(["payment_upload", ext], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, ext == ".csv" ? "text/csv" : XlsxExporter::MIME_TYPE, original_filename: "payment#{ext}")
  end

  UPLOAD_HEADERS = ["Bill ID", "Name", "Transaction ID", "Transaction Type (NEFT/RTGS/IMPS)", "Transaction Date (DD/MM/YYYY)"].freeze

  test "month key keeps financial years apart and options sort newest first" do
    controller = ModulesController.new
    assert_equal "October|2026-2027", controller.send(:jeevika_payment_month_key, " october ", "2026-2027")
    assert_equal "", controller.send(:jeevika_payment_month_key, "-", "2026-2027")
    rows = [
      { bill_month: "April", financial_year: "2026-2027" },
      { bill_month: "March", financial_year: "2025-2026" },
      { bill_month: "October", financial_year: "2026-2027" },
      { bill_month: "January", financial_year: "2026-2027" }
    ]
    assert_equal ["January|2026-2027", "October|2026-2027", "April|2026-2027", "March|2025-2026"],
      controller.send(:jeevika_payment_month_options, rows)
  end

  test "screen save by bill month pays every selected bill of that month" do
    with_fake_sms do
      post payment_details_module_path(SLUG), params: { module_record: {
        payment_month: "October|2026-2027", selected_bill_ids: [@oct_a.id, @oct_b.id],
        transaction_id: "TXN-#{@tag}", transaction_type: "neft", transaction_date: "2026-11-01"
      } }
    end

    assert_redirected_to module_path(SLUG, payment_month: "October|2026-2027")
    record = payments.last
    assert_equal [@oct_a.id.to_s, @oct_b.id.to_s].sort, record.data["selected_bill_ids"].sort
    assert_equal "2026-10-29, 2026-10-28", record.data["approval_date"]
    assert_equal "October", record.data["bill_month"]
    assert_equal "NEFT", record.data["transaction_type"]
    assert_not record.data.key?("payment_month")
    assert_equal 2, @sms_calls.size
  end

  test "screen save rejects a bill from another month" do
    assert_no_difference -> { payments.count } do
      post payment_details_module_path(SLUG), params: { module_record: {
        payment_month: "October|2026-2027", selected_bill_ids: [@oct_a.id, @sep.id],
        transaction_id: "TXN", transaction_type: "NEFT", transaction_date: "2026-11-01"
      } }
    end
    assert_match "bill month", flash[:alert]
  end

  test "old approval date save still works unchanged" do
    with_fake_sms do
      post payment_details_module_path(SLUG), params: { module_record: {
        approval_date: "2026-10-29", selected_bill_ids: [@oct_a.id],
        transaction_id: "OLD", transaction_type: "IMPS", transaction_date: "2026-11-01"
      } }
    end
    assert_equal "2026-10-29", payments.last.data["approval_date"]
    assert_match "saved successfully", flash[:notice]
  end

  test "excel upload groups rows by transaction and skips blank rows" do
    file = upload_file(UPLOAD_HEADERS, [
      [@oct_a.id, "Pay JJ", "T1-#{@tag}", "NEFT", "01/11/2026"],
      [@oct_b.id, "Pay JJ", "T1-#{@tag}", "neft", "01/11/2026"],
      [@sep.id, "Pay JJ", "", "", ""]
    ])

    with_fake_sms do
      assert_difference -> { payments.count }, 1 do
        post payment_details_upload_module_path(SLUG), params: { payment_excel_file: file }
      end
    end

    record = payments.last
    assert_equal [@oct_a.id.to_s, @oct_b.id.to_s].sort, record.data["selected_bill_ids"].sort
    assert_equal "2026-11-01", record.data["transaction_date"]
    assert_equal "excel", record.data["upload_source"]
    assert record.data["excel_file"].present?
    assert_redirected_to module_path(SLUG, payment_tab: "updated")
    assert_match "2 Jeevika Jankar", flash[:notice]
  end

  test "excel upload with any bad row saves nothing" do
    file = upload_file(UPLOAD_HEADERS, [
      [@oct_a.id, "Pay JJ", "T2", "NEFT", "01/11/2026"],
      [@oct_b.id, "Pay JJ", "T2", "CASH", "01/11/2026"],
      [999_999_999, "Nobody", "T3", "NEFT", "2026-11-01"]
    ], ext: ".csv")

    assert_no_difference -> { payments.count } do
      post payment_details_upload_module_path(SLUG), params: { payment_excel_file: file }
    end
    assert_match "Kuch save nahi hua", flash[:alert]
    assert_match "Row 3", flash[:alert]
    assert_match "Row 4", flash[:alert]
  end

  test "excel upload refuses an already updated bill" do
    with_fake_sms do
      post payment_details_upload_module_path(SLUG), params: { payment_excel_file: upload_file(UPLOAD_HEADERS, [[@oct_a.id, "", "T4", "RTGS", "01/11/2026"]]) }
    end
    assert_equal "2026-11-01", payments.last.data["transaction_date"], "DD/MM/YYYY is read day first"

    assert_no_difference -> { payments.count } do
      post payment_details_upload_module_path(SLUG), params: { payment_excel_file: upload_file(UPLOAD_HEADERS, [[@oct_a.id, "", "T5", "RTGS", "02/11/2026"]]) }
    end
    assert_match "pehle se update", flash[:alert]
  end

  test "only DD/MM/YYYY dates and NEFT/RTGS/IMPS types are accepted" do
    bad_dates = ["46327", "2026-11-01", "1/11/2026", "01-11-2026", "31/02/2026", "11/2026"]
    rows = bad_dates.map { |date| [@oct_a.id, "", "T6", "NEFT", date] }
    rows << [@oct_b.id, "", "T6", "UPI", "01/11/2026"]
    upload = JeevikaPaymentBulkUpload.new(upload_file(UPLOAD_HEADERS, rows, ext: ".csv"), transaction_types: %w[NEFT RTGS IMPS])

    assert_empty upload.rows
    assert_equal bad_dates.size + 1, upload.errors.size
    assert(upload.errors.first(bad_dates.size).all? { |error| error.include?("DD/MM/YYYY") })
    assert_match "NEFT/RTGS/IMPS", upload.errors.last
  end

  test "a row with only some transaction details is an error, a fully blank row is skipped" do
    rows = [
      [@oct_a.id, "", "", "NEFT", "01/11/2026"],
      [@oct_b.id, "", "", "", ""]
    ]
    upload = JeevikaPaymentBulkUpload.new(upload_file(UPLOAD_HEADERS, rows, ext: ".csv"), transaction_types: %w[NEFT])

    assert_empty upload.rows
    assert_equal ["Row 2: Transaction ID khali hai."], upload.errors
  end

  test "format file carries the type dropdown, the date rule and text columns" do
    get payment_details_format_module_path(SLUG)
    Tempfile.create(["format", ".xlsx"], binmode: true) do |tmp|
      tmp.write(response.body)
      tmp.flush
      Zip::File.open(tmp.path) do |zip|
        sheet = zip.read("xl/worksheets/sheet1.xml")
        assert_includes sheet, %(type="list")
        assert_includes sheet, %(<formula1>"NEFT,RTGS,IMPS"</formula1>)
        assert_match(/sqref="K2:K\d+"/, sheet)
        assert_includes sheet, %(type="custom")
        assert_match(/sqref="L2:L\d+"/, sheet)
        assert_match(/<col min="10" max="10"[^>]*style="1"/, sheet)
        assert_includes zip.read("xl/styles.xml"), %(numFmtId="49")
      end
    end
  end

  test "format download lists only not updated bills of the month" do
    get payment_details_format_module_path(SLUG, payment_month: "October|2026-2027")
    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type

    Tempfile.create(["format", ".xlsx"], binmode: true) do |tmp|
      tmp.write(response.body)
      tmp.flush
      upload = Rack::Test::UploadedFile.new(tmp.path, XlsxExporter::MIME_TYPE, original_filename: "f.xlsx")
      sheet_rows = JeevikaPaymentBulkUpload.new(upload, transaction_types: %w[NEFT]).send(:raw_rows)
      assert_equal "Email", sheet_rows.first[4]
      assert_includes sheet_rows.drop(1).map { |row| row[4].to_s }, @vrp.email
      ids = sheet_rows.drop(1).map { |row| row[0].to_s }
      assert_includes ids, @oct_a.id.to_s
      assert_includes ids, @oct_b.id.to_s
      assert_not_includes ids, @sep.id.to_s
    end
  end

  test "tabs show not updated and updated bills by month" do
    get module_path(SLUG)
    assert_response :success
    assert_select ".payment-status-tab", 2
    assert_select "select[name='module_record[payment_month]'] option[value='October|2026-2027']"
    assert_select "tr[data-payment-month='October|2026-2027']", minimum: 2

    with_fake_sms do
      post payment_details_module_path(SLUG), params: { module_record: {
        payment_month: "September|2026-2027", selected_bill_ids: [@sep.id],
        transaction_id: "TAB-#{@tag}", transaction_type: "NEFT", transaction_date: "2026-11-01"
      } }
    end

    get module_path(SLUG, payment_tab: "updated", payment_month: "September|2026-2027")
    assert_response :success
    assert_select "#jeevika_jankar_updated_payment_table td", text: "TAB-#{@tag}"
  end
end
