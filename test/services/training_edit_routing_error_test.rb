require "test_helper"

# The submit error used to say "assign an Agronomist" no matter why routing
# failed, so someone whose office already had two would add a third.
class TrainingEditRoutingErrorTest < ActiveSupport::TestCase
  OFFICE = "FCO-Bhawanipatna".freeze

  setup do
    @requester = { "id" => 1, "record_type" => "User", "username" => "jj_user", "fcoc" => OFFICE }
    @training = { "fco_name" => OFFICE }
  end

  def agronomist(id, name)
    User.create!(user_name: name.parameterize.underscore, password: "secret", first_name: name,
      role: "Agronomist", office_name: OFFICE, user_type: "User", status: "Active").tap do |user|
      user.update_columns(id: id) if user.id != id
    end
  end

  test "no Agronomist on the office says exactly that, and names the office" do
    message = TrainingEditApproval.routing_error(@training, @requester)

    assert_match(/No active Agronomist account is assigned/, message)
    assert_match(/FCO-Bhawanipatna/, message)
    assert_match(/User List/, message)
  end

  test "two Agronomists on the office says there are too many, and names them" do
    agronomist(901, "Asha Verma")
    agronomist(902, "Bimal Rao")

    message = TrainingEditApproval.routing_error(@training, @requester)
    assert_match(/2 active Agronomist accounts are assigned/, message)
    assert_match(/Asha Verma, Bimal Rao/, message)
    assert_match(/deactivate or move the others/, message)
  end

  test "being the office's only Agronomist says an edit cannot approve itself" do
    only = agronomist(903, "Chandra Sahu")
    actor = { "id" => only.id, "record_type" => "User", "username" => only.user_name, "fcoc" => OFFICE }

    message = TrainingEditApproval.routing_error(@training, actor)
    assert_match(/You are the only Agronomist assigned/, message)
    assert_match(/cannot be approved by its own author/, message)
  end

  test "exactly one eligible Agronomist is not an error at all" do
    agronomist(904, "Deepa Nag")

    assert_nil TrainingEditApproval.routing_error(@training, @requester)
    routing = TrainingEditApproval.automatic_routing(@training, @requester)
    assert_equal ["Deepa Nag"], routing["approvers"]
    assert_equal OFFICE, routing["approval_office"]
  end

  test "an inactive Agronomist does not count as assigned" do
    agronomist(905, "Esha Patel").update!(status: "Inactive")

    assert_match(/No active Agronomist account is assigned/,
      TrainingEditApproval.routing_error(@training, @requester))
  end
end

# Replacing an Agronomist used to strand every request already waiting with
# the old one: assign_automatic_approver! skipped anything already routed.
class TrainingEditRerouteTest < ActiveSupport::TestCase
  OFFICE = "FCO-Bhawanipatna".freeze

  def agronomist(name, status: "Active")
    User.create!(user_name: name.parameterize.underscore, password: "secret", first_name: name,
      role: "Agronomist", office_name: OFFICE, user_type: "User", status: status)
  end

  def pending_revision(approver)
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "record_id" => 1, "status" => "Pending", "step" => 0,
      "before" => { "fco_name" => OFFICE }, "proposed" => {},
      "requester" => { "id" => 999, "record_type" => "User", "username" => "cc_user" },
      "requester_identity" => "User:999",
      "approvers" => [TrainingStaffScope.name(approver)],
      "approver_identities" => ["User:#{approver.id}"],
      "approval_office" => OFFICE, "approval_role" => "agronomist", "history" => []
    })
  end

  test "a pending request moves to the Agronomist who replaced the old one" do
    old = agronomist("Asha Verma")
    revision = pending_revision(old)

    # The office changes hands: the old account is retired, a new one takes over.
    old.update!(status: "Inactive")
    replacement = agronomist("Bimal Rao")

    TrainingEditApproval.assign_automatic_approver!(revision)

    assert_equal ["Bimal Rao"], revision.data["approvers"]
    assert_equal ["User:#{replacement.id}"], revision.data["approver_identities"]
    assert_equal "agronomist", revision.data["approval_role"]
  end

  test "the handover is written into the request's history" do
    old = agronomist("Asha Verma")
    revision = pending_revision(old)
    old.update!(status: "Inactive")
    agronomist("Bimal Rao")

    TrainingEditApproval.assign_automatic_approver!(revision)

    entry = revision.data["history"].last
    assert_equal "reassigned", entry["action"]
    assert_equal "Asha Verma", entry["from"]
    assert_equal "Bimal Rao", entry["to"]
  end

  test "a request whose Agronomist is still in place is left alone" do
    still_there = agronomist("Asha Verma")
    revision = pending_revision(still_there)
    before = revision.data.deep_dup

    TrainingEditApproval.assign_automatic_approver!(revision)

    assert_equal before, revision.data, "nothing should be rewritten on every page render"
  end

  test "with no Agronomist left the request is unassigned rather than left with a retired one" do
    old = agronomist("Asha Verma")
    revision = pending_revision(old)
    old.update!(status: "Inactive")

    TrainingEditApproval.assign_automatic_approver!(revision)

    assert_empty revision.data["approvers"]
    assert_nil revision.data["approval_role"]
    assert_equal "unassigned", revision.data["history"].last["to"]
  end

  test "a decided request is never rerouted" do
    old = agronomist("Asha Verma")
    revision = pending_revision(old)
    revision.update!(data: revision.data.merge("status" => "Approved"))
    old.update!(status: "Inactive")
    agronomist("Bimal Rao")

    TrainingEditApproval.assign_automatic_approver!(revision)
    assert_equal ["Asha Verma"], revision.reload.data["approvers"]
  end
end

# Rerouting must never fire on a guess. These are the shapes that carry no
# evidence either way; touching them unassigned requests that were fine.
class TrainingEditRerouteSafetyTest < ActiveSupport::TestCase
  def revision_with(extra)
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "record_id" => 1, "status" => "Pending", "step" => 0,
      "before" => {}, "proposed" => {}, "history" => [],
      "approval_role" => "agronomist", "approvers" => ["Approver"]
    }.merge(extra))
  end

  test "a request routed by name only, with no identity, is left untouched" do
    revision = revision_with("approval_office" => "FCO-Bhawanipatna")
    before = revision.data.deep_dup

    TrainingEditApproval.assign_automatic_approver!(revision)
    assert_equal before, revision.data
  end

  test "a request with no stored office is left untouched" do
    revision = revision_with("approver_identities" => ["User:5"])
    before = revision.data.deep_dup

    TrainingEditApproval.assign_automatic_approver!(revision)
    assert_equal before, revision.data
  end
end
