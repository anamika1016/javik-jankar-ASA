require "test_helper"

class ApprovalUserLabelsTest < ActionDispatch::IntegrationTest
  setup do
    @finance = User.create!(user_name: "Prabhajot", password: "secret", first_name: "Prabhajot", last_name: "Singh", role: "PD-Finance", user_type: "User", status: "Active")
    @admin = User.create!(user_name: "label_admin", password: "secret", first_name: "Admin", user_type: "admin", status: "Active")
    @step = ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Bill", "approval_level" => "Third Approval",
      "approver_approved_by" => "Prabhajot Singh (PMC-Oprection)", "status" => "Active"
    })
  end

  test "approval list shows current User List role for a stale saved approver" do
    post login_path, params: { login: @admin.user_name, password: "secret" }
    get module_path("approval-list")
    assert_response :success
    assert_select ".approval-level-item small", text: "Prabhajot Singh (PD-Finance)"
    refute_includes response.body, "PMC-Oprection"
    assert_equal "Prabhajot Singh (PMC-Oprection)", @step.reload.data["approver_approved_by"]
  end

  test "pending bill label uses current approver role without altering approval identity" do
    controller = ModulesController.new
    step = @step
    controller.define_singleton_method(:jeevika_bill_approval_history) { |_| [] }
    controller.define_singleton_method(:jeevika_bill_approval_steps) { |_| [step] }
    controller.define_singleton_method(:jeevika_bill_current_approval_step) { |_| step }
    bill = ModuleRecord.new(data: { "status" => "Pending at Prabhajot Singh (PMC-Oprection)" })
    assert_equal "Pending at Prabhajot Singh (PD-Finance)", controller.send(:jeevika_bill_status_label, bill)
    assert_equal "Prabhajot Singh (PD-Finance)", controller.send(:module_record_field_value, @step, "Approver (Approved By)")
  end

  test "directory resolves exact usernames and leaves missing or ambiguous people intact" do
    User.create!(user_name: "another_prabhajot", password: "secret", first_name: "Prabhajot", last_name: "Singh", role: "Manager")
    directory = ApprovalUserDisplayDirectory.new
    assert_equal "Prabhajot Singh (PD-Finance)", directory.label("Prabhajot(PMC-Oprection)")
    assert_equal "Prabhajot Singh (PMC-Oprection)", directory.label("Prabhajot Singh (PMC-Oprection)")
    assert_equal "Missing Person (PMC)", directory.label("Missing Person (PMC)")
  end

  test "a new request reflects an updated User List role and batches lookups" do
    directory = ApprovalUserDisplayDirectory.new
    assert_equal "Prabhajot Singh (PD-Finance)", directory.label(@step.data["approver_approved_by"])
    @finance.update!(role: "Finance Director")
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, "sql.active_record") do
      updated = ApprovalUserDisplayDirectory.new
      30.times { assert_equal "Prabhajot Singh (Finance Director)", updated.label(@step.data["approver_approved_by"]) }
    end
    assert_equal 1, queries.grep(/FROM "users"/).size
  end
end
