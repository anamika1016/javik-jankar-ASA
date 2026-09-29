require "test_helper"

class JeevikaBillInvoiceTest < ActiveSupport::TestCase
  setup { @controller = ModulesController.new }

  test "worksheet uses actual date attendance instead of repeating monthly total" do
    def @controller.jeevika_bill_training_attendance_by_date(_item)
      { "2026-09-01" => %w[1 2], "2026-09-14" => %w[3] }
    end
    record = ModuleRecord.new(data: { "bill_items" => [{ "achievement_count" => "137", "timesheet_dates" => "2026-09-01,2026-09-14", "main_activity" => "Farmers Training", "activity" => "Organic" }] })
    rows = @controller.send(:jeevika_bill_time_slot_rows, record)
    assert_equal [2, 1], rows.map { |row| row[:number] }
    assert_equal "Farmers Training", rows.first[:tci]
    assert_equal "Organic", rows.first[:activity]
  end

  test "a first approval is not mislabeled financial approval" do
    def @controller.jeevika_bill_approval_history(_record)
      [ModuleRecord.new(data: { "action" => "Approved", "approval_level" => "First Approver" }),
       ModuleRecord.new(data: { "action" => "Approved", "approval_level" => "Fourth Approver" })]
    end
    assert_equal ["First Approver", "Financial Approver"], @controller.send(:jeevika_bill_approved_by_rows, ModuleRecord.new).map(&:first)
  end

  test "prepared by ignores a placeholder name and uses the saved creator login" do
    def @controller.jeevika_bill_approval_history(_); []; end
    def @controller.bill_creator_user(_); nil; end
    def @controller.bill_creator_module_record(_); nil; end
    def @controller.jeevika_bill_vrp(_); nil; end
    record = ModuleRecord.new(data: { "created_by_name" => "-", "created_by_username" => "cc.login" }, created_at: Time.current)
    assert_equal "cc.login", @controller.send(:jeevika_bill_prepared_by, record)[:name]
  end

  test "farmer identity has village father and tracenet without mobile" do
    helper = Object.new.extend(ApplicationHelper)
    assert_equal "Village: Bandhan | Father: Pratap | Tracenet: 519", helper.farmer_identity_meta("Bandhan", "Pratap", "519")
    assert_equal "Village: - | Father: - | Tracenet: -", helper.farmer_identity_meta("NULL", nil, "")
    assert ApplicationHelper::SIDEBAR_SECTIONS.any? { |section| section[:links].any? { |link| link.first == "Observation List" } }
  end
  test "pending badge checks past twenty requests and clears after approval" do
    21.times do |index|
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
        "status" => "Pending", "approval_role" => "agronomist", "approvers" => ["other"],
        "approver_identities" => ["User:#{index + 100}"]
      })
    end
    pending = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "status" => "Pending", "approval_role" => "agronomist", "approvers" => ["reviewer"],
      "approver_identities" => ["User:42"], "step" => 0
    })
    helper = Object.new.extend(ApplicationHelper)
    def helper.current_app_user; { "record_type" => "User", "id" => 42, "username" => "reviewer" }; end
    assert helper.compute_sidebar_pending_flags["Training Form List"]
    pending.update!(data: pending.data.merge("status" => "Approved"))
    assert_not helper.compute_sidebar_pending_flags["Training Form List"]
  end

end
