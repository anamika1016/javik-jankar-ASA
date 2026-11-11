require "test_helper"

# An edit goes to the Jeevika Jankar's own owner: "Transfer By" when the JJ
# has been transferred, otherwise "Registered By". Routing by "the one
# Agronomist on the FCO office" blocked every edit as soon as an office had
# two Agronomists covering different TOs, which is a normal arrangement.
class TrainingEditOwnerRoutingTest < ActiveSupport::TestCase
  OFFICE = "FCO-Bhawanipatna".freeze

  setup do
    @registrar = User.create!(user_name: "sms_ag", password: "secret", first_name: "Vedantika",
      last_name: "Sadangi", role: "Agronomist", office_name: OFFICE, user_type: "User", status: "Active")
    @other_agronomist = User.create!(user_name: "sms_af", password: "secret", first_name: "Durga Prasad",
      last_name: "Pati", role: "Agronomist", office_name: OFFICE, user_type: "User", status: "Active")
    # Routing only reads the ownership columns; the rest of the Jeevika Jankar
    # validations are not what this test is about.
    @vrp = Vrp.new(name: "JJ One", user_name: "jj_one", fcoc: OFFICE,
      mobile_no: "9876543210", aadhar_no: "123456789012", account_no: "123",
      address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current, experience_in_years: 0, father_husband_name: "Test",
      gender: 1, ifsc_code: "TEST0123456", office_detail_id: 0, to_office_detail_id: 0,
      email: "jj_one@example.test", bank_name: "SBI", status: 55,
      created_by_id: @registrar.id, created_by_type: "User")
    @vrp.save!(validate: false)
    @training = { "jeevika_jankar_id" => @vrp.id, "fco_name" => OFFICE }
    @cc = { "id" => 500, "record_type" => "User", "username" => "cc_user", "fcoc" => OFFICE }
  end

  test "two Agronomists on one office no longer block the edit" do
    assert_equal 2, TrainingStaffScope.staff(OFFICE, :agronomist).size

    routing = TrainingEditApproval.automatic_routing(@training, @cc)
    assert_equal ["Vedantika Sadangi"], routing["approvers"]
    assert_nil TrainingEditApproval.routing_error(@training, @cc)
  end

  test "the edit goes to Registered By when the Jeevika Jankar was never transferred" do
    routing = TrainingEditApproval.automatic_routing(@training, @cc)

    assert_equal ["User:#{@registrar.id}"], routing["approver_identities"]
    assert_equal "jeevika_jankar_owner", routing["approval_role"]
    assert_equal OFFICE, routing["approval_office"]
  end

  test "once transferred, the edit goes to Transfer By instead" do
    receiver = User.create!(user_name: "new_owner", password: "secret", first_name: "Akash",
      last_name: "Raut", role: "Agronomist", office_name: OFFICE, user_type: "User", status: "Active")
    ModuleRecord.create!(module_slug: "jeevika-jankar-transfer", data: {
      "user_name" => "Akash Raut (Agronomist)", "status" => "Active",
      "jeevika_jankar_names" => ["JJ One - #{@vrp.id}"]
    })

    routing = TrainingEditApproval.automatic_routing(@training, @cc)
    assert_equal ["Akash Raut"], routing["approvers"]
    assert_equal ["User:#{receiver.id}"], routing["approver_identities"]
  end

  test "a transfer for a different Jeevika Jankar does not move this one" do
    User.create!(user_name: "other_owner", password: "secret", first_name: "Akash", last_name: "Raut",
      role: "Agronomist", office_name: OFFICE, user_type: "User", status: "Active")
    ModuleRecord.create!(module_slug: "jeevika-jankar-transfer", data: {
      "user_name" => "Akash Raut", "status" => "Active",
      "jeevika_jankar_names" => ["Someone Else - #{@vrp.id + 777}"]
    })

    assert_equal ["Vedantika Sadangi"], TrainingEditApproval.automatic_routing(@training, @cc)["approvers"]
  end

  test "an inactive transfer record is ignored and the registrar keeps it" do
    User.create!(user_name: "stale_owner", password: "secret", first_name: "Akash", last_name: "Raut",
      role: "Agronomist", office_name: OFFICE, user_type: "User", status: "Active")
    ModuleRecord.create!(module_slug: "jeevika-jankar-transfer", data: {
      "user_name" => "Akash Raut", "status" => "Inactive",
      "jeevika_jankar_names" => ["JJ One - #{@vrp.id}"]
    })

    assert_equal ["Vedantika Sadangi"], TrainingEditApproval.automatic_routing(@training, @cc)["approvers"]
  end

  test "when the owner is the one editing, it falls back to the other Agronomist" do
    actor = { "id" => @registrar.id, "record_type" => "User", "username" => @registrar.user_name }

    routing = TrainingEditApproval.automatic_routing(@training, actor)
    assert_equal ["Durga Prasad Pati"], routing["approvers"],
      "an edit cannot be approved by its own author, so it goes to the office Agronomist"
    assert_nil TrainingEditApproval.routing_error(@training, actor)
  end

  test "the owner editing with nobody else to fall back to is told why" do
    @other_agronomist.update!(status: "Inactive")
    actor = { "id" => @registrar.id, "record_type" => "User", "username" => @registrar.user_name }

    message = TrainingEditApproval.routing_error(@training, actor)
    assert_match(/registered to you/, message)
    assert_match(/cannot be approved by its own author/, message)
  end

  test "a Jeevika Jankar with no owner at all says so plainly" do
    @vrp.update_columns(created_by_id: nil, created_by_type: nil)

    message = TrainingEditApproval.routing_error(@training, @cc)
    assert_match(/no "Registered By" or "Transfer By" user on record/, message)
  end

  test "a training with no Jeevika Jankar still falls back to the office Agronomist" do
    @other_agronomist.update!(status: "Inactive")
    detached = { "fco_name" => OFFICE }

    routing = TrainingEditApproval.automatic_routing(detached, @cc)
    assert_equal ["Vedantika Sadangi"], routing["approvers"]
    assert_equal "agronomist", routing["approval_role"]
  end
end
