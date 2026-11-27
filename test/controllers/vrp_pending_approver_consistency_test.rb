require "test_helper"

# The approval channel a Jeevika Jankar belongs to is decided by the identities
# of whoever registered it. vrp_creator_identities also appended the identity of
# whoever happened to be looking, so a record that was sent to one approver read
# "Pending at <someone else>" as soon as a different person opened the list.
#
# The viewer's identity is now a fallback for records with no resolvable
# creator, nothing more. These tests pin that one record reads the same to
# everyone, and that the fallback still works.
class VrpPendingApproverConsistencyTest < ActionDispatch::IntegrationTest
  setup do
    @creator = User.create!(user_name: "chan_creator", password: "secret",
      first_name: "Chan", last_name: "Creator", role: "FCO-Sausar",
      stakeholder: "ASA", office_name: "FCO-Sausar", user_type: "User", status: "Active")

    # approval_channel_key includes user_name, so these are two separate
    # channels rather than two steps of one. The first is the creator's, the
    # second belongs to the viewer further down - before the fix, simply being
    # that viewer was enough to pull the record onto it.
    channel_step("ASA", "FCO-Sausar", "First Approval",
      "Shailesh Bagde (agricultural specialist)", "chan_creator")
    channel_step("ASA", "FCO-C Sausar", "First Approval",
      "Hemant shakkrapude (FCO-C Sausar)", "chan_viewer")

    @vrp = jeevika_jankar
    @viewer = User.create!(user_name: "chan_viewer", password: "secret",
      first_name: "Hemant", last_name: "shakkrapude", role: "FCO-C Sausar",
      stakeholder: "ASA", office_name: "FCO-C Sausar", user_type: "User", status: "Active")
    @outsider = User.create!(user_name: "chan_outsider", password: "secret",
      first_name: "Anamika", last_name: "Vishwakarma", role: "IT Excicutive",
      stakeholder: "ASA", office_name: "PAPL", user_type: "User", status: "Active")
  end

  def channel_step(stakeholder, office, level, approver, user_name)
    ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Registration", "stakeholder_name" => stakeholder,
      "sub_office_name" => office, "approval_level" => level,
      "approver_approved_by" => approver, "user_name" => user_name,
      "status" => "Active"
    })
  end

  def jeevika_jankar
    vrp = Vrp.new(
      name: "Anuu", father_husband_name: "sukhi sahu", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "334455667788", account_no: "3344556677", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "9330000001", email: "anuu_chan@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 1, password: "secret",
      user_name: "anuu_chan", fcoc: "FCO-Sausar",
      created_by_id: @creator.id, created_by_type: "User"
    )
    vrp.save!(validate: false)
    ModuleRecord.create!(module_slug: "vrp-approval-history", data: {
      "vrp_id" => vrp.id.to_s, "action" => "Sent for Approval",
      "approval_level" => "First Approval"
    })
    vrp
  end

  def status_for(user)
    post login_path, params: { login: user.user_name, password: "secret" }
    get vrps_path
    assert_response :success
    controller = @controller
    label = controller.send(:vrp_status_label, Vrp.find(@vrp.id))
    delete logout_path rescue nil
    reset!
    label
  end

  test "one record reads the same pending approver to every viewer" do
    seen_by_outsider = status_for(@outsider)
    seen_by_viewer = status_for(@viewer)

    assert_equal seen_by_outsider, seen_by_viewer,
      "the same Jeevika Jankar showed a different pending approver to a " \
      "different login, so the status depended on who was looking"
  end

  test "the pending approver is the one the record was sent to" do
    assert_equal "Pending at Shailesh Bagde (agricultural specialist)", status_for(@outsider)
    assert_equal "Pending at Shailesh Bagde (agricultural specialist)", status_for(@viewer),
      "an approver opening the list must not re-route the record onto their own channel"
  end

  test "a record with no resolvable creator still falls back to the viewer" do
    orphan = Vrp.new(
      name: "Orphan JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "334455667799", account_no: "3344556688", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "9330000002", email: "orphan_chan@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 1, password: "secret",
      user_name: "orphan_chan", fcoc: "FCO-C Sausar"
    )
    orphan.save!(validate: false)

    post login_path, params: { login: @viewer.user_name, password: "secret" }
    get vrps_path
    assert_response :success

    identities = @controller.send(:vrp_creator_identities, Vrp.find(orphan.id))
    assert identities.any?,
      "a record with no creator must still fall back to the current login"
  end
end
