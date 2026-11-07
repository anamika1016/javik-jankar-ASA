require "test_helper"

class BillMutationRedirectTest < ActiveSupport::TestCase
  test "bill send redirects with GET semantics after preserving status and history writes" do
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Draft" })
    controller = build_controller(bill)
    step = ModuleRecord.new(data: { "approver_approved_by" => "Reviewer", "approval_level" => "First Approval" })
    controller.define_singleton_method(:jeevika_bill_approval_steps) { |_| [step] }
    writes = []
    controller.define_singleton_method(:update_bill_status!) { |record, status, **kwargs| writes << [record.id, status, kwargs] }
    controller.define_singleton_method(:create_bill_approval_history) { |record, action, actual_step| writes << [record.id, action, actual_step] }
    controller.send_bill_for_approval
    assert_equal 303, controller.response.status
    assert_match %r{/modules/jeevika-jankar-bill-list\z}, controller.response.location
    assert_equal "Pending at Reviewer", writes.first[1]
    assert_equal [bill.id, "Sent for Approval", step], writes.last
  end

  test "missing channel and denied bill redirects also use GET semantics" do
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Draft" })
    controller = build_controller(bill)
    controller.define_singleton_method(:jeevika_bill_approval_steps) { |_| [] }
    controller.send_bill_for_approval
    assert_equal 303, controller.response.status
    assert_match(/approval channel/, controller.flash[:alert])
    controller = build_controller(bill)
    controller.define_singleton_method(:jeevika_jankar_bill_record_visible?) { |_| false }
    controller.send_bill_for_approval
    assert_equal 303, controller.response.status
    assert_equal "You are not allowed to view this bill.", controller.flash[:alert]
  end

  private

  def build_controller(bill)
    controller = ModulesController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.set_response!(ActionDispatch::TestResponse.new)
    controller.params = ActionController::Parameters.new(id: bill.id)
    controller.define_singleton_method(:load_module!) { @slug = "jeevika-jankar-bill-list" }
    controller.define_singleton_method(:jeevika_jankar_bill_record_visible?) { |_| true }
    controller
  end
end
