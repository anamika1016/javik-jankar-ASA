require "test_helper"

# A login can be a User, a Vrp (Jeevika Jankar) or a new-user ModuleRecord, and
# each of those tables has its own id sequence. Records store both the creator's
# id and created_by_record_type, but the target-record visibility check compared
# the id alone - so User #9 was treated as the creator of a training record that
# Vrp #9 had saved, and inherited a different cluster's data.
#
# The bill screens already guard this with a record-type check. These tests pin
# the same guard on training/other-target records, and pin that the legitimate
# matches it must keep allowing are unaffected.
class TargetRecordCreatorIdentityTest < ActiveSupport::TestCase
  setup do
    @jj = Vrp.create!(
      name: "Mahesh Lavale", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "771234567890", account_no: "7712345678", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "9770000001", email: "mahesh_jj@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, password: "secret",
      user_name: "mahesh_jj", fcoc: "FCO-Bhawanipatna",
      cluster_incharge: "Chumki Bag (Cluster Incharge)"
    )

    # The collision: a different person in a different table with the same id.
    @user = User.create!(id: @jj.id, user_name: "ganesh_cc", password: "secret",
      first_name: "Ganesh", last_name: "Lokhande", role: "Cluster Incharge",
      email: "ganesh_cc@example.com", office_name: "FCO-Betul",
      user_type: "User", status: "Active")

    @record = training_record(created_by_id: @jj.id.to_s, created_by_record_type: "Vrp",
      created_by_username: @jj.user_name, created_by_name: @jj.name)
  end

  def training_record(extra)
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "fco_name" => "FCO-Bhawanipatna",
      "gram_name" => "JODABANDH", "trainer_name" => "Jyosnamayi Suna"
    }.merge(extra.transform_keys(&:to_s)))
  end

  def controller_for(login)
    controller = ModulesController.new
    payload = controller.send(:app_user_session_payload, login)
    controller.define_singleton_method(:current_app_user) { payload }
    controller
  end

  test "a User does not inherit a record created by the Vrp with the same id" do
    controller = controller_for(@user)

    assert_not controller.send(:target_record_created_by_current_user?, @record),
      "a User was treated as the creator of a Jeevika Jankar's record because the ids collided"
  end

  test "the Jeevika Jankar who actually created it is still the creator" do
    controller = controller_for(@jj)

    assert controller.send(:target_record_created_by_current_user?, @record),
      "the Jeevika Jankar lost ownership of a record they created"
  end

  test "a User still owns a record they created themselves" do
    mine = training_record(created_by_id: @user.id.to_s, created_by_record_type: "User",
      created_by_username: @user.user_name)

    assert controller_for(@user).send(:target_record_created_by_current_user?, mine)
  end

  test "a record saved before the type was recorded keeps the old id match" do
    # No created_by_record_type at all. Dropping these would take records away
    # from whoever can currently see them, so the type-blind match is kept.
    legacy = training_record(created_by_id: @user.id.to_s)

    assert controller_for(@user).send(:target_record_created_by_current_user?, legacy),
      "a legacy record without a creator type stopped matching its owner"
  end

  test "a new-user ModuleRecord creator still matches the matching User login" do
    # Linked to the same person by email; the user_name column is unique across
    # logins so the legacy row carries its own.
    new_user = ModuleRecord.create!(module_slug: "new-user", data: {
      "user_name" => "ganesh_cc_legacy", "name" => "Ganesh Lokhande",
      "email" => @user.email, "password" => "secret", "status" => "Active"
    })
    linked = training_record(created_by_id: new_user.id.to_s,
      created_by_record_type: "ModuleRecord", created_by_username: @user.user_name)

    assert controller_for(@user).send(:target_record_created_by_current_user?, linked),
      "the legacy new-user link a User login relies on was broken"
  end

  test "name and contact matching is unaffected by the id guard" do
    by_name = training_record(created_by_username: @user.user_name)

    assert controller_for(@user).send(:target_record_created_by_current_user?, by_name),
      "matching on the creator's username stopped working"
  end
end
