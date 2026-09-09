require "test_helper"

class TrainingEditApprovalTest < ActiveSupport::TestCase
  setup do
    @actor = { "id" => "123", "record_type" => "User", "username" => "training_editor" }
    @first = { "id" => "124", "username" => "first_approver" }
    @second = { "id" => "125", "username" => "second_approver" }
    [@first, @second].each_with_index do |actor, index|
      ModuleRecord.create!(module_slug: "approval-master", data: {
        "module_name" => "Training Form Edit", "status" => "Active",
        "user_name" => @actor["username"], "approval_level" => "Level #{index + 1}",
        "approver_approved_by" => actor["username"]
      })
    end
    @record = ModuleRecord.create!(module_slug: "training-form", data: {
      "training_description" => "Original", "created_by_id" => "49",
      "training_register_upload" => "/uploads/module_records/old.png"
    })
  end

  test "uploads and ownership survive and only final approval applies changes" do
    revision = TrainingEditApproval.submit!(record: @record, actor: @actor, proposed: {
      "training_description" => "Edited", "created_by_id" => "123",
      "training_register_upload" => "/uploads/module_records/new.png"
    })
    assert_equal "Original", @record.reload.data["training_description"]
    assert_equal "49", revision.data["proposed"]["created_by_id"]
    assert_equal 2, revision.data["proposed"]["training_register_upload"].size
    assert_includes TrainingEditApproval.unapproved_record_ids, @record.id.to_s
    assert_not TrainingEditApproval.can_decide?(revision, @second)
    TrainingEditApproval.decide!(revision: revision, actor: @first, decision: "approve", remarks: "Checked")
    assert_equal "Original", @record.reload.data["training_description"]
    TrainingEditApproval.decide!(revision: revision, actor: @second, decision: "approve", remarks: "Checked")
    assert_equal "Edited", @record.reload.data["training_description"]
    assert_not_includes TrainingEditApproval.unapproved_record_ids, @record.id.to_s
  end

  test "returned changes stay out of billing and can be resubmitted" do
    revision = TrainingEditApproval.submit!(record: @record, actor: @actor, proposed: @record.data.merge("training_description" => "Edited"))
    assert_raises(TrainingEditApproval::InvalidTransition) do
      TrainingEditApproval.submit!(record: @record, actor: @actor, proposed: @record.data)
    end
    TrainingEditApproval.decide!(revision: revision, actor: @first, decision: "reject", remarks: "Correct details")
    assert_equal "Returned", revision.reload.data["status"]
    assert_equal "Original", @record.reload.data["training_description"]
    assert_includes TrainingEditApproval.unapproved_record_ids, @record.id.to_s
    untouched = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July" })
    assert_not_includes TrainingEditApproval.unapproved_record_ids, untouched.id.to_s
    retry_revision = TrainingEditApproval.submit!(record: @record, actor: @actor, proposed: @record.data)
    assert_equal "Pending", retry_revision.data["status"]
  end
end
