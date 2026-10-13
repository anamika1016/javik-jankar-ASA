require "test_helper"

# The invoice worksheet only lists lines that actually achieved something, and a
# cluster incharge sees the bills of the Jeevika Jankars mapped under them.
class JeevikaBillWorksheetAndCcTest < ActionDispatch::IntegrationTest
  def other_item(achievement:, activity: "Village level farmers groups")
    {
      "main_activity_type" => "other", "main_activity" => "Farmers WhatsApp Groups",
      "activity" => activity, "village" => "Bahpur", "achievement_count" => achievement
    }
  end

  def bill_with_items(items, month: "September", **data)
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "bill_month" => month, "select_vrp" => "1", "status" => "Pending at Someone"
    }.merge(data).merge("bill_items" => items))
  end

  def worksheet_rows(record)
    controller = ModulesController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.send(:jeevika_bill_time_slot_rows, record)
  end

  test "a line that achieved nothing is left off the invoice" do
    record = bill_with_items([other_item(achievement: "50", activity: "Farmer Registration"),
                              other_item(achievement: "0")])

    rows = worksheet_rows(record)
    assert_equal 1, rows.size, "the zero line should not reach the invoice"
    assert_equal "Farmer Registration", rows.first[:activity]
  end

  test "every line is kept when they all achieved something" do
    record = bill_with_items([other_item(achievement: "50", activity: "A"),
                              other_item(achievement: "2", activity: "B")])

    assert_equal %w[A B], worksheet_rows(record).map { |row| row[:activity] }.sort
  end

  # A blank count is read as zero, so it drops like any other zero.
  test "a decimal zero and a blank count both drop" do
    assert_empty worksheet_rows(bill_with_items([other_item(achievement: "0.00")]))
    assert_empty worksheet_rows(bill_with_items([other_item(achievement: "")]))
  end

  # The guard only removes a genuinely numeric zero, so a row carrying text is
  # never silently dropped.
  test "a non numeric count is never treated as zero" do
    controller = ModulesController.new
    assert controller.send(:jeevika_bill_worksheet_row_empty?, { number: "0" })
    assert controller.send(:jeevika_bill_worksheet_row_empty?, { number: 0 })
    assert_not controller.send(:jeevika_bill_worksheet_row_empty?, { number: "-" })
    assert_not controller.send(:jeevika_bill_worksheet_row_empty?, { number: "N/A" })
    assert_not controller.send(:jeevika_bill_worksheet_row_empty?, { number: "3" })
  end

  test "a cluster incharge sees the bills of the Jeevika Jankars under them" do
    cc = User.create!(user_name: "ws_cc", password: "secret", first_name: "Pawan",
                      last_name: "Uikey", role: "Cluster Incharge",
                      office_name: "FCO-C Sausar", user_type: "User", status: "Active")
    mine = vrp("MINE JJ", "9000000031", cluster_incharge: "Pawan Uikey (Cluster Incharge)")
    theirs = vrp("THEIRS JJ", "9000000032", cluster_incharge: "Other CC")

    my_bill = bill_with_items([other_item(achievement: "5")], select_vrp: mine.id.to_s)
    my_bill.update!(data: my_bill.data.merge("select_vrp" => mine.id.to_s))
    other_bill = bill_with_items([other_item(achievement: "5")], select_vrp: theirs.id.to_s)
    other_bill.update!(data: other_bill.data.merge("select_vrp" => theirs.id.to_s))

    post login_path, params: { login: cc.user_name, password: "secret" }
    get module_path("jeevika-jankar-bill-list")
    assert_response :success

    assert_includes response.body, "MINE JJ", "the mapped Jeevika Jankar's bill should be listed"
    assert_not_includes response.body, "THEIRS JJ",
      "another cluster incharge's bill must not be listed"
  end

  def vrp(name, mobile, **extra)
    Vrp.create!({
      name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "ws#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: "FCO-C Sausar"
    }.merge(extra))
  end
end
