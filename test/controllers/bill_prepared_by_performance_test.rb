require "test_helper"

class BillPreparedByPerformanceTest < ActiveSupport::TestCase
  test "primary prepared names retain precedence and dates without identity fallbacks" do
    [[" CC Name ", "Creator", "CC Name"], [nil, " Creator ", "Creator"],
      ["NULL", "Creator", "Creator"], ["-", "Creator", "Creator"]].each do |cc, creator, expected|
      controller = ModulesController.new
      history = ModuleRecord.new(data: { "action" => "Sent for Approval", "action_at" => "2026-11-09 10:00" })
      controller.define_singleton_method(:jeevika_bill_approval_history) { |_| [history] }
      controller.define_singleton_method(:jeevika_bill_cc_name) { |_| cc }
      controller.define_singleton_method(:bill_display_datetime) { |value| value }
      %i[bill_creator_user bill_creator_module_record jeevika_jankar_vrp_label jeevika_bill_vrp].each do |method|
        controller.define_singleton_method(method) { |*| raise "Unused identity fallback: #{method}" }
      end
      bill = ModuleRecord.new(data: { "created_by_name" => creator })
      assert_equal({ name: expected, at: "2026-11-09 10:00" }, controller.send(:jeevika_bill_prepared_by, bill))
    end
  end

  test "invalid primary labels retain user fallback and record timestamp" do
    controller = ModulesController.new
    controller.define_singleton_method(:jeevika_bill_approval_history) { |_| [] }
    controller.define_singleton_method(:jeevika_bill_cc_name) { |_| "nil" }
    controller.define_singleton_method(:bill_display_datetime) { |value| value }
    controller.define_singleton_method(:jeevika_jankar_display_name) { |value| value }
    controller.define_singleton_method(:jeevika_jankar_vrp_label) { |_| "JJ" }
    controller.define_singleton_method(:jeevika_bill_vrp) { |_| nil }
    controller.define_singleton_method(:bill_creator_user) { |_| Struct.new(:full_name, :user_name).new("User Name", "user") }
    bill = ModuleRecord.new(data: { "created_by_name" => " - " }, created_at: Time.zone.parse("2026-11-09 09:00"))
    assert_equal({ name: "User Name", at: bill.created_at }, controller.send(:jeevika_bill_prepared_by, bill))
  end
end
