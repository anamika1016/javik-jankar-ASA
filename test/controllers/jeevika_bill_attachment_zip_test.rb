require "test_helper"

# A bill row can carry a dozen photos. Those download as one archive so the row
# stays readable, while PDFs and spreadsheets keep their own links.
class JeevikaBillAttachmentZipTest < ActionDispatch::IntegrationTest
  UPLOAD_ROOT = Rails.root.join("public", "uploads", "module_records")

  setup do
    FileUtils.mkdir_p(UPLOAD_ROOT)
    @written = []
    # The suite runs in parallel workers that share public/uploads, so each test
    # needs its own filenames or one worker's teardown deletes another's files.
    @tag = "zip_probe_#{SecureRandom.hex(6)}"
    @photo_a = write_upload("#{@tag}_a.jpg", "image-bytes-a")
    @photo_b = write_upload("#{@tag}_b.png", "image-bytes-b")
    @pdf = write_upload("#{@tag}_doc.pdf", "%PDF-fake")
    @xlsx = write_upload("#{@tag}_sheet.xlsx", "xlsx-fake")

    @vrp = Vrp.create!(
      name: "ZIP JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: "9876500077",
      email: "zip#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: "FCO-C Sausar"
    )

    @admin = User.create!(user_name: "zip_admin", password: "secret", first_name: "Adm",
                          user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  teardown { @written.each { |path| FileUtils.rm_f(path) } }

  def write_upload(name, content)
    path = UPLOAD_ROOT.join(name)
    File.binwrite(path, content)
    @written << path
    "/uploads/module_records/#{name}"
  end

  # An "Other" bill row pulls its uploads from the other-target record that
  # shares its target mapping, so build that chain for real.
  def bill_with_uploads(urls)
    target = TargetMapping.create!(
      vrp_id: @vrp.id, fco_id: "1", ics_id: "1", village_id: "1", month_name: "July",
      main_activity_name: "Seed Distribution", activity_name: "Sub",
      target_quantity: 1, afl_ids: "[]"
    )
    ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => target.id.to_s, "attachment_upload" => urls, "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "bill_month" => "July", "select_vrp" => @vrp.id.to_s, "status" => "Final Approved",
      "bill_items" => [{
        "main_activity_type" => "other", "target_mapping_id" => target.id.to_s,
        "main_activity" => "Seed Distribution", "activity" => "Sub"
      }]
    })
  end

  # open_buffer's behaviour depends on whether the body arrives as a String or
  # an IO, which differs between a single file run and the full suite. Writing
  # it out first keeps the assertions deterministic.
  def with_zip
    Tempfile.create(["bill_photos", ".zip"], binmode: true) do |file|
      body = response.body
      file.write(body.respond_to?(:read) ? body.read : body.to_s)
      file.flush
      Zip::File.open(file.path) { |zip| yield zip }
    end
  end

  def zip_entry_names
    with_zip { |zip| zip.map(&:name) }
  end

  test "only the photos land in the archive" do
    record = bill_with_uploads([@photo_a, @photo_b, @pdf, @xlsx])

    get download_bill_attachments_module_record_path("jeevika-jankar-bill-list", record, item: 0)
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_equal ["#{@tag}_a.jpg", "#{@tag}_b.png"].sort, zip_entry_names.sort,
      "documents must stay out of the photo archive"
  end

  test "the archive keeps the real file contents" do
    record = bill_with_uploads([@photo_a])

    get download_bill_attachments_module_record_path("jeevika-jankar-bill-list", record, item: 0)
    with_zip do |zip|
      assert_equal "image-bytes-a", zip.find_entry("#{@tag}_a.jpg").get_input_stream.read
    end
  end

  test "a row with only documents says so instead of sending an empty archive" do
    record = bill_with_uploads([@pdf, @xlsx])

    get download_bill_attachments_module_record_path("jeevika-jankar-bill-list", record, item: 0)
    assert_redirected_to module_path("jeevika-jankar-bill-list")
    assert_equal "No photo is saved on this row.", flash[:alert]
  end

  test "a login that cannot see the bill cannot download its photos" do
    record = bill_with_uploads([@photo_a])
    outsider = User.create!(user_name: "zip_outsider", password: "secret", first_name: "Out",
                            role: "Manager ics", office_name: "PAPL",
                            user_type: "User", status: "Active")
    post login_path, params: { login: outsider.user_name, password: "secret" }

    get download_bill_attachments_module_record_path("jeevika-jankar-bill-list", record, item: 0)
    assert_redirected_to module_path("jeevika-jankar-bill-list")
    assert_equal "You are not allowed to download these attachments.", flash[:alert]
  end

  # A bill row only ever shows the month it bills. A training uploaded in
  # another month must never reach the row, with or without billed dates.
  test "another month's training upload never reaches the row" do
    target = TargetMapping.create!(
      vrp_id: @vrp.id, fco_id: "1", ics_id: "1", village_id: "1", month_name: "July",
      main_activity_name: "Farmers' Training", activity_name: "Sub",
      target_quantity: 1, afl_ids: %w[1].to_json
    )
    july = training_record(target, "2026-07-10", "#{@tag}_july.pdf")
    august = training_record(target, "2026-08-10", "#{@tag}_august.pdf")

    controller = ModulesController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.define_singleton_method(:bill_training_targets) { |_ids| [target] }
    controller.define_singleton_method(:target_farmer_ids) { |_target| ["1"] }
    controller.define_singleton_method(:matching_training_records_for_target) do |_t, _ids|
      # The month gate lives upstream of this seam, so assert it directly too.
      [july, august].select { |record| send(:training_record_matches_month?, record, "July") }
    end

    urls = controller.send(:jeevika_bill_training_uploads, { "target_mapping_id" => target.id })
    assert urls.any? { |url| url.include?("#{@tag}_july.pdf") }, "the billed month's upload should show"
    assert_not urls.any? { |url| url.include?("#{@tag}_august.pdf") },
      "an upload from another month must not show on this row"
  end

  def training_record(target, date, pdf_name)
    write_upload(pdf_name, "%PDF-#{pdf_name}")
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => Date.parse(date).strftime("%B"), "training_date" => date,
      "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => ["1"],
      "main_activity" => "Farmers' Training", "sub_activity" => "Sub",
      "training_register_upload" => "/uploads/module_records/#{pdf_name}"
    })
  end

  # Uploads may live on the shared server instead of this machine. A local file
  # is always preferred; the remote fallback only applies in development, so the
  # suite never reaches out over the network.
  test "a local upload is read from disk without any remote call" do
    controller = ModulesController.new
    controller.define_singleton_method(:remote_module_upload_body) do |_name|
      raise "must not fall back to the network when the file is on disk"
    end

    file = controller.send(:module_upload_attachment_file, @photo_a)
    assert_equal "#{@tag}_a.jpg", file[:name]
    assert_equal "image-bytes-a", file[:content]
  end

  test "a missing upload returns nothing instead of raising" do
    controller = ModulesController.new
    assert_nil controller.send(:module_upload_attachment_file, "/uploads/module_records/not_here_#{@tag}.jpg")
  end

  test "the remote fallback stays off outside development" do
    controller = ModulesController.new
    assert_not Rails.env.development?, "the suite must not run in development"
    assert_nil controller.send(:remote_module_upload_body, "anything.jpg")
  end

  # Attachment holds the photo archive; Files lists the documents.
  test "the detail screen splits Attachment and Files into their own columns" do
    record = bill_with_uploads([@photo_a, @photo_b, @pdf])

    get module_path("jeevika-jankar-bill-list", view_id: record.id)
    assert_response :success

    assert_includes response.body, "<th>Attachment</th>"
    assert_includes response.body, "<th>Files</th>"
    assert_includes response.body, "PHOTOS (2)"
    assert_includes response.body, "PDF"
    assert_not_includes response.body, "JPEG 1",
      "photos should no longer be listed one by one"
  end

  test "each row keeps one Attachment cell and one Files cell" do
    record = bill_with_uploads([@photo_a, @pdf])

    get module_path("jeevika-jankar-bill-list", view_id: record.id)
    body = response.body
    header_count = body.scan(%r{<th>(?:Attachment|Files)</th>}).size
    assert_equal 2, header_count, "both columns should appear exactly once"

    row = body[%r{<tr>(?:(?!</tr>).)*PHOTOS \(1\).*?</tr>}m]
    assert row, "the billed row should render"
    assert_equal 2, row.scan(/class="bill-activity-attachments"/).size,
      "the row needs a cell for each of the two columns"
  end

  # A row with only documents still lines up: Attachment shows a dash.
  test "a row with no photo still fills both columns" do
    record = bill_with_uploads([@pdf])

    get module_path("jeevika-jankar-bill-list", view_id: record.id)
    assert_response :success
    row = response.body[%r{<tr>(?:(?!</tr>).)*bill-activity-attachments.*?</tr>}m]
    assert_equal 2, row.scan(/class="bill-activity-attachments"/).size
    assert_includes row, "bill-attachment-empty", "Attachment should show a dash"
    assert_includes row, "PDF"
  end
end
