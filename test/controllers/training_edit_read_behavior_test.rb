require "test_helper"

class TrainingEditReadBehaviorTest < ActionDispatch::IntegrationTest
  test "opening training edit retains legacy page routing without publishing proposed data" do
    admin = User.create!(user_name: "read_audit_admin", first_name: "Audit Admin", password: "secret",
      user_type: "admin", status: "Active")
    agronomist = User.create!(user_name: "read_audit_agronomist", first_name: "Audit Approver", password: "secret",
      role: "Agronomist", office_name: "FCO-C Sausar", status: "Active")
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Training Form", "Training Form List"], "can_view" => "Yes", "status" => "Active"
    })
    original = { "month" => "October", "fco_name" => "FCO-C Sausar", "training_location" => "Original location" }
    training = ModuleRecord.create!(module_slug: "training-form", data: original)
    older = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => training.id.to_s, "status" => "Approved" })
    latest = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, created_at: 1.year.ago, data: {
      "record_id" => training.id.to_s, "status" => "Pending", "before" => original,
      "proposed" => original.merge("training_location" => "Proposed location"), "requester" => {}, "approvers" => []
    })
    unrelated = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: latest.data.merge("record_id" => "0#{training.id}"))
    older_attributes = older.attributes.deep_dup

    post login_path, params: { login: admin.user_name, password: "secret" }
    assert_no_difference("ModuleRecord.count") { get edit_module_record_path("training-form", training) }
    assert_response :success
    assert_equal original, training.reload.data
    assert_equal "Pending", latest.reload.data["status"]
    assert_equal "agronomist", latest.data["approval_role"]
    assert_equal ["User:#{agronomist.id}"], latest.data["approver_identities"]
    assert_equal original.merge("training_location" => "Proposed location"), latest.data["proposed"]
    assert_equal older_attributes, older.reload.attributes
    # The existing sidebar routes all visible pending requests as it renders.
    # Keep that page-level behavior as well as the targeted edit helper read.
    assert_equal "Pending", unrelated.reload.data["status"]
    assert_equal original, unrelated.data["before"]
    assert_equal latest.data["proposed"], unrelated.data["proposed"]
    assert_equal ["User:#{agronomist.id}"], unrelated.data["approver_identities"]

    assigned = latest.attributes.deep_dup
    get edit_module_record_path("training-form", training)
    assert_response :success
    assert_equal assigned, latest.reload.attributes
    assert_equal original, training.reload.data
  end
end
