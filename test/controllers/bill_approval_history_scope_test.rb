require "test_helper"

# jeevika_bill_approval_history_by_bill_id groups every approval-history row by
# the bill it belongs to. List screens announce the rows they are about to show
# so the load stays narrow, but the member actions (approve/reject/return) work
# on a single bill and announced nothing - so approving one bill read the whole
# approval-history table and grouped it in Ruby.
#
# update_bill_approval now announces that single id. These tests pin that the
# history the approving code actually reads is byte for byte what the full load
# produced, and that the no-scope and empty-scope behaviours are untouched.
class BillApprovalHistoryScopeTest < ActiveSupport::TestCase
  HISTORY_SLUG = "jeevika-jankar-bill-approval-history".freeze

  setup do
    @bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process",
      data: { "bill_month" => "October" })
    @other_bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process",
      data: { "bill_month" => "October" })

    # Two runs on the subject bill, with an edit boundary between them, so the
    # ordering and the boundary logic both have something to bite on.
    @entries = [
      history_for(@bill, "Sent for Approval", "First Approval"),
      history_for(@bill, "Approved", "First Approval"),
      history_for(@bill, "Bill Edited", "First Approval"),
      history_for(@bill, "Sent for Approval", "First Approval"),
      history_for(@bill, "Approved", "Second Approval")
    ]
    # Noise that a full table load would pull in and a scoped load would not.
    3.times { history_for(@other_bill, "Approved", "First Approval") }
  end

  def history_for(bill, action, level)
    ModuleRecord.create!(module_slug: HISTORY_SLUG, data: {
      "bill_id" => bill.id.to_s, "action" => action, "approval_level" => level,
      "approver" => "Someone", "remarks" => "ok", "action_by" => "Tester",
      "action_at" => Time.current.iso8601
    })
  end

  def controller_scoped_to(ids)
    controller = ModulesController.new
    controller.instance_variable_set(:@jeevika_bill_history_record_ids, ids) unless ids == :unset
    controller
  end

  test "scoped and unscoped loads give the approving code the same history" do
    unscoped = controller_scoped_to(:unset).send(:jeevika_bill_approval_history, @bill)
    scoped = controller_scoped_to([@bill.id.to_s]).send(:jeevika_bill_approval_history, @bill)

    assert_equal @entries.map(&:id), unscoped.map(&:id)
    assert_equal unscoped.map(&:id), scoped.map(&:id),
      "narrowing the history load changed what the bill's own history looks like"
    assert_equal unscoped.map { |h| h.data["action"] }, scoped.map { |h| h.data["action"] }
  end

  test "the current-run boundary resolves the same way on both paths" do
    unscoped = controller_scoped_to(:unset).send(:jeevika_bill_current_approval_history, @bill)
    scoped = controller_scoped_to([@bill.id.to_s]).send(:jeevika_bill_current_approval_history, @bill)

    # Everything after the last "Sent for Approval" / "Bill Edited" marker.
    assert_equal ["Approved"], unscoped.map { |h| h.data["action"] }
    assert_equal unscoped.map(&:id), scoped.map(&:id)
  end

  test "the scoped load stops reading other bills' history rows" do
    controller = controller_scoped_to([@bill.id.to_s])

    loaded = controller.send(:jeevika_bill_approval_history_by_bill_id)

    assert_equal [@bill.id.to_s], loaded.keys,
      "the narrowed load still pulled in rows belonging to other bills"
    assert_empty controller.send(:jeevika_bill_approval_history, @other_bill),
      "a bill outside the announced scope must read as having no history"
  end

  test "announcing no ids still yields no history, as the list path does" do
    # defined? is true but the value is empty - the existing visible-ids branch
    # maps that to scope.none, and this branch has to agree.
    controller = controller_scoped_to([])

    assert_empty controller.send(:jeevika_bill_approval_history_by_bill_id)
    assert_empty controller.send(:jeevika_bill_approval_history, @bill)
  end

  test "the visible-ids branch still wins when both are announced" do
    controller = ModulesController.new
    controller.instance_variable_set(:@jeevika_bill_visible_record_ids, [@other_bill.id.to_s])
    controller.instance_variable_set(:@jeevika_bill_history_record_ids, [@bill.id.to_s])

    assert_equal [@other_bill.id.to_s],
      controller.send(:jeevika_bill_approval_history_by_bill_id).keys,
      "the list screen's scope must keep priority over the member-action scope"
  end

  test "a bill with no history still reads as an empty list" do
    fresh = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process",
      data: { "bill_month" => "November" })
    controller = controller_scoped_to([fresh.id.to_s])

    assert_empty controller.send(:jeevika_bill_approval_history, fresh)
  end
end
