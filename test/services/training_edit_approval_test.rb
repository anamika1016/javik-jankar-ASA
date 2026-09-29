require "test_helper"

class TrainingEditApprovalTest < ActiveSupport::TestCase
  test "CC edits route to the owning Agronomist without an approval channel" do
    record = ModuleRecord.create!(module_slug: "training-form", data: { "fco_name" => "FCO-C Sausar", "month" => "August", "training_location" => "Original", "selected_farmer_ids" => ["1"] })
    fco = User.create!(user_name: "sausar_fco", password: "secret", first_name: "Sausar", last_name: "Approver",
      stakeholder_role: "Agronomist", office_name: "FCO-C Sausar")
    approver = { "id" => fco.id, "record_type" => "User", "user_type" => "user", "username" => fco.user_name }
    cc = { "id" => "10", "record_type" => "User", "username" => "cc_user", "name" => "CC Display Name" }
    revision = TrainingEditApproval.submit!(record: record, proposed: record.data.merge("training_location" => "Changed", "selected_farmer_ids" => ["1", "2"]), actor: cc)

    assert_equal "Original", record.reload.data["training_location"]
    assert_equal "Pending", revision.data["status"]
    assert_equal "Pending at Sausar Approver", TrainingEditApproval.status_label(revision)
    assert TrainingEditApproval.can_decide?(revision, approver)

    TrainingEditApproval.decide!(revision: revision, actor: approver, decision: "approve", remarks: "Verified")

    assert_equal "Changed", record.reload.data["training_location"]
    assert_equal %w[1 2], record.data["selected_farmer_ids"]
    assert_equal "Approved", revision.reload.data["status"]
    assert_equal "Approved", TrainingEditApproval.status_label(revision)
  end

  test "routing uses original office and account identity, not edited office or matching names" do
    fco = User.create!(user_name: "own_fco", password: "secret", first_name: "Same Name",
      stakeholder_role: "Agronomist", office_name: "FCO-C Sausar")
    other = User.create!(user_name: "other_fco", password: "secret", first_name: "Same Name",
      stakeholder_role: "Agronomist", office_name: "FCO-C Turekela")
    record = ModuleRecord.create!(module_slug: "training-form", data: { "fco_name" => "FCO-C Sausar" })
    revision = TrainingEditApproval.submit!(record: record, proposed: { "fco_name" => "FCO-C Turekela" },
      actor: { "id" => "99999", "record_type" => "User" })
    assert_equal ["User:#{fco.id}"], revision.data["approver_identities"]
    refute TrainingEditApproval.visible?(revision, { "id" => other.id, "record_type" => "User", "name" => "Same Name" })
    refute TrainingEditApproval.can_decide?(revision, { "id" => other.id, "record_type" => "User", "name" => "Same Name" })
  end

  test "unassigned old request automatically finds its FCO" do
    fco = User.create!(user_name: "legacy_fco", password: "secret", first_name: "Legacy",
      role: "Agronomist", office_name: "FCO-C Sausar")
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "status" => "Pending", "before" => { "fco_name" => "FCO-C Sausar" }, "approvers" => [], "requester" => {} })
    TrainingEditApproval.assign_automatic_approver!(revision)
    assert_equal ["User:#{fco.id}"], revision.reload.data["approver_identities"]
  end

  test "pending FCO request is reassigned to Agronomist" do
    user = User.create!(user_name: "replacement_agronomist", password: "secret", first_name: "Shailesh",
      role: "Agronomist", office_name: "FCO-C Sausar")
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "status" => "Pending", "step" => 0, "before" => { "fco_name" => "FCO-C Sausar" },
      "requester" => {}, "approvers" => ["Hemant Shakkarpude"], "approver_identities" => ["User:99999"] })
    TrainingEditApproval.assign_automatic_approver!(revision)
    assert_equal ["Shailesh"], revision.reload.data["approvers"]
    assert_equal "agronomist", revision.data["approval_role"]
    refute TrainingEditApproval.can_decide?(revision, { "id" => 99999, "record_type" => "User" })
    assert TrainingEditApproval.can_decide?(revision, { "id" => user.id, "record_type" => "User" })
  end

  test "requester can revise pending changes without publishing or duplicating the request" do
    User.create!(user_name: "pending_editor_agronomist", password: "secret", first_name: "Approver",
      role: "Agronomist", office_name: "FCO-C Sausar")
    actor = { "id" => "99991", "record_type" => "User" }
    record = ModuleRecord.create!(module_slug: "training-form", data: {
      "fco_name" => "FCO-C Sausar", "training_location" => "Original" })
    revision = TrainingEditApproval.submit!(record: record, proposed: record.data.merge("training_location" => "First edit"), actor: actor)
    assert_equal "First edit", TrainingEditApproval.edit_data(record, actor)["training_location"]
    assert_includes TrainingEditApproval.pending_for(actor).map(&:id), revision.id
    assert_no_difference('ModuleRecord.where(module_slug: TrainingEditApproval::SLUG).count') do
      updated = TrainingEditApproval.submit!(record: record, proposed: record.data.merge("training_location" => "Second edit"), actor: actor)
      assert_equal revision.id, updated.id
    end
    assert_equal "Original", record.reload.data["training_location"]
    assert_equal "Second edit", revision.reload.data["proposed"]["training_location"]
    assert_equal "Pending", revision.data["status"]
    assert_equal "resubmitted", revision.data["history"].last["action"]
    other = { "id" => "99992", "record_type" => "User" }
    assert_equal "Original", TrainingEditApproval.edit_data(record, other)["training_location"]
    assert_raises(TrainingEditApproval::InvalidTransition) do
      TrainingEditApproval.submit!(record: record, proposed: record.data, actor: other)
    end
    revision.update!(data: revision.data.merge("status" => "Approved"))
    assert_empty TrainingEditApproval.pending_for(actor)
  end

  test "missing FCO does not create an unrouted request" do
    record = ModuleRecord.create!(module_slug: "training-form", data: { "fco_name" => "Unassigned Office" })
    assert_no_difference('ModuleRecord.where(module_slug: TrainingEditApproval::SLUG).count') do
      assert_raises(TrainingEditApproval::InvalidTransition) do
        TrainingEditApproval.submit!(record: record, proposed: record.data, actor: { "id" => "99999" })
      end
    end
  end

  test "approver identified by display name and extra spaces can still decide" do
    revision = ModuleRecord.new(data: {
      "status" => "Pending", "step" => 0,
      "approvers" => ["Shailesh  Bagde (agricultural specialist)"]
    })
    # Login username is just "Shailesh" while the channel stored the full display name.
    approver = { "user_type" => "user", "username" => "Shailesh", "name" => "Shailesh  Bagde", "mobile_no" => "7000280864" }
    submitter = { "user_type" => "user", "username" => "Ashvin", "name" => "Ashvin  Durve" }

    assert TrainingEditApproval.can_decide?(revision, approver), "the named approver should be able to decide"
    assert TrainingEditApproval.visible?(revision, approver)
    refute TrainingEditApproval.can_decide?(revision, submitter), "the submitter must not decide"
  end
  test "approval preserves unrelated live edits while publishing CC removal" do
    before = { "fco_name" => "FCO-C Sausar", "cluster_coordinator_name" => "Coordinator", "training_location" => "Old" }
    record = ModuleRecord.create!(module_slug: "training-form", data: before.merge("training_location" => "New"))
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "record_id" => record.id, "before" => before,
      "proposed" => before.merge("cluster_coordinator_name" => "N/A"),
      "status" => "Pending", "step" => 0, "approval_role" => "agronomist",
      "approvers" => ["Approver"], "history" => []
    })
    TrainingEditApproval.decide!(revision: revision, actor: { "user_type" => "admin", "id" => 1 }, decision: "approve", remarks: "Verified")
    assert_equal "N/A", record.reload.data["cluster_coordinator_name"]
    assert_equal "New", record.data["training_location"]
    assert_equal "Approved", revision.reload.data["status"]
  end

  test "merge accepts already applied changes but rejects same field and office conflicts" do
    before = { "cluster_coordinator_name" => "A", "fco_name" => "Sausar" }
    proposed = before.merge("cluster_coordinator_name" => "N/A")
    assert_equal proposed, TrainingEditApproval.merge_approved_data(before: before, proposed: proposed, current: proposed)
    [{ "cluster_coordinator_name" => "B" }, { "fco_name" => "Turekela" }].each do |change|
      error = assert_raises(TrainingEditApproval::InvalidTransition) do
        TrainingEditApproval.merge_approved_data(before: before, proposed: proposed, current: before.merge(change))
      end
      assert_includes error.message, change.keys.first
    end
  end

  test "email backfill does not block approve or reject and latest email is retained" do
    %w[approve reject].each do |decision|
      before = { "created_by_id" => "40", "created_by_record_type" => "Vrp",
        "cluster_coordinator_name" => "Coordinator" }
      current = before.merge("created_by_email" => "current@example.test")
      record = ModuleRecord.create!(module_slug: "training-form", data: current)
      revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
        "record_id" => record.id, "before" => before,
        "proposed" => before.merge("cluster_coordinator_name" => "N/A", "created_by_email" => "stale@example.test"),
        "status" => "Pending", "step" => 0, "approval_role" => "agronomist",
        "approvers" => ["Approver"], "history" => []
      })
      TrainingEditApproval.decide!(revision: revision, actor: { "user_type" => "admin", "id" => 1 }, decision: decision, remarks: "Reviewed")
      assert_equal decision == "approve" ? "Approved" : "Rejected", revision.reload.data["status"]
      assert_equal "current@example.test", record.reload.data["created_by_email"]
      assert_equal decision == "approve" ? "N/A" : "Coordinator", record.data["cluster_coordinator_name"]
    end
  end

  test "creator identity changes remain protected even when email changes" do
    before = { "created_by_id" => "40", "created_by_record_type" => "Vrp", "created_by_email" => "old@example.test" }
    assert_raises(TrainingEditApproval::InvalidTransition) do
      TrainingEditApproval.merge_approved_data(before: before, proposed: before,
        current: before.merge("created_by_id" => "41", "created_by_email" => "new@example.test"))
    end
  end
end
