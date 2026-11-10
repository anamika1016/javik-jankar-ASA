require "test_helper"

class BillIndexReuseTest < ActiveSupport::TestCase
  test "complete other-target index misses retain bill fallback without rebuilding the index" do
    controller = ModulesController.new
    controller.define_singleton_method(:jeevika_jankar_activity_setting_for) { |*| { main_activity_type: "Other" } }
    controller.define_singleton_method(:approved_other_target_achievement_index) { raise "Complete index must not be rebuilt for each missing target" }
    target = TargetMapping.new(id: 42, month_name: "October", main_activity_name: "Visit", activity_name: "Work", target_quantity: 10)
    bill = ModuleRecord.new(data: { "select_bill_month" => "October", "bill_items" => [{ "activity" => "Work", "no_of_unit" => "3" }] })
    actual = controller.send(:vrp_target_completed_quantity, target, [bill], activity_settings: {}, sub_activity_settings: {},
      other_target_achievement_index: {}, other_target_achievement_index_complete: true)
    assert_equal 3, actual
    actual = controller.send(:vrp_target_completed_quantity, target, [bill], activity_settings: {}, sub_activity_settings: {},
      other_target_achievement_index: { "42" => { achievement: 15 } }, other_target_achievement_index_complete: true)
    assert_equal 10, actual
  end

  test "partial and absent indexes retain the original authoritative fallback" do
    controller = ModulesController.new
    controller.define_singleton_method(:jeevika_jankar_activity_setting_for) { |*| { main_activity_type: "Other" } }
    controller.define_singleton_method(:approved_other_target_achievement_index) { { "42" => { achievement: 7 } } }
    target = TargetMapping.new(id: 42, target_quantity: 10)
    [nil, {}, { "other" => { achievement: 2 } }].each do |index|
      assert_equal 7, controller.send(:vrp_target_completed_quantity, target, [], activity_settings: {}, sub_activity_settings: {},
        other_target_achievement_index: index)
    end
  end
  test "status candidates use calculated status and preserve pending as the complement of final approved" do
    controller = ModulesController.new
    statuses = ["Final Approved", "Pending at Reviewer", "Submitted (Not sent for approval)", "Rejected", "Returned", "pending-completed-by-history"]
    records = statuses.each_with_index.map do |status, i|
      ModuleRecord.new(id: i + 1, data: { "status" => status, "bill_month" => "October", "record_state" => "Active" })
    end
    controller.define_singleton_method(:jeevika_bill_status_label) do |record|
      record.data["status"] == "pending-completed-by-history" ? "Final Approved" : record.data["status"]
    end
    %w[pending final-approved].each do |status|
      expected = records.select do |record|
        final = controller.send(:jeevika_bill_status_label, record).downcase.include?("final approved")
        status == "final-approved" ? final : !final
      end
      actual = controller.send(:jeevika_bill_list_candidates, records, month: "october", record_state: "active", status: status)
      assert_equal expected.map(&:id), actual.map(&:id)
    end
    assert_equal records, controller.send(:jeevika_bill_list_candidates, records, month: nil, record_state: nil)
    assert_empty controller.send(:jeevika_bill_list_candidates, records, month: "November", record_state: nil, status: "pending")
  end

  test "real terminal approval history enters final bucket and edit boundary restores pending bucket" do
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Pending at Reviewer", "bill_month" => "October" })
    step = ModuleRecord.new(id: 777, data: { "approval_level" => "Final Approval", "approver_approved_by" => "Reviewer" })
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: {
      "bill_id" => bill.id.to_s, "action" => "Approved", "approval_level" => "Final Approval", "approver" => "Reviewer" })
    calculator = lambda do
      ModulesController.new.tap do |controller|
        controller.define_singleton_method(:jeevika_bill_approval_steps) { |_| [step] }
      end
    end
    controller = calculator.call
    assert_equal "Final Approved", controller.send(:jeevika_bill_status_label, bill)
    assert_equal [bill], controller.send(:jeevika_bill_list_candidates, [bill], month: "October", record_state: nil, status: "final-approved")
    assert_empty controller.send(:jeevika_bill_list_candidates, [bill], month: "October", record_state: nil, status: "pending")
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: { "bill_id" => bill.id.to_s, "action" => "Bill Edited" })
    bill.update!(data: bill.data.merge("status" => "Submitted (Not sent for approval)"))
    controller = calculator.call
    assert_equal [bill], controller.send(:jeevika_bill_list_candidates, [bill], month: "October", record_state: nil, status: "pending")
    assert_empty controller.send(:jeevika_bill_list_candidates, [bill], month: "October", record_state: nil, status: "final-approved")
  end

end
