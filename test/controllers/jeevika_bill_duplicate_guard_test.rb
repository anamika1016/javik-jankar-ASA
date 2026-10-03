require "test_helper"

# A Jeevika Jankar disappears from the Bill Process dropdown once they already
# have a bill for the selected month. This documents exactly which bills block.
class JeevikaBillDuplicateGuardTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    @controller.define_singleton_method(:model_ready?) { |_| true }
    @controller.define_singleton_method(:params) { {} }
  end

  def bill(vrp_id:, month: "September", **data)
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process",
                         data: { "select_vrp" => vrp_id.to_s, "bill_month" => month }.merge(data))
  end

  def blocked_vrp_ids
    @controller.send(:jeevika_jankar_existing_bill_keys).map { |item| item[:vrp_id] }
  end

  test "an existing bill for the month hides that Jeevika Jankar" do
    bill(vrp_id: 93)
    assert_includes blocked_vrp_ids, "93"
  end

  test "a bill for another month does not hide them" do
    bill(vrp_id: 93, month: "August")
    keys = @controller.send(:jeevika_jankar_existing_bill_keys)
    assert_equal ["August"], keys.map { |item| item[:month] }
  end

  test "a deleted or inactive bill stops blocking" do
    bill(vrp_id: 93, "deleted" => "true")
    bill(vrp_id: 94, "record_state" => "Inactive")
    assert_empty blocked_vrp_ids
  end

  # A rejected or returned bill is dead - the Jeevika Jankar has to be billed
  # again for that month, so it must not keep blocking the dropdown.
  test "a rejected or returned bill does not block re-billing" do
    bill(vrp_id: 93, "status" => "Rejected by Second Approver")
    bill(vrp_id: 94, "status" => "Returned by First Approver")

    assert_empty blocked_vrp_ids,
      "a rejected/returned bill must not block the Jeevika Jankar from being billed again"
  end
end
