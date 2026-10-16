require "test_helper"

# The approval is parked at a person by name. A name saved with a stray double
# space, or a first name carrying a trailing one, used to read as a different
# person, so the very user it was waiting on could not act on it.
class Api::V1::JeevikaJankarApproverMatchingTest < ActionDispatch::IntegrationTest
  APPROVER = "Anurag Patel (PMC-Oprection)".freeze

  test "the approver can approve when their saved name has stray spaces" do
    approver("Anurag ", " Patel", "spaced")
    jj = send_for_approval("spaced")

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "ok" },
      headers: auth("appr_spaced"), as: :json

    assert_response :success
    assert_equal 55, jj.reload.status.to_i
  end

  test "the approver can approve when their name is saved cleanly" do
    approver("Anurag", "Patel", "clean")
    jj = send_for_approval("clean")

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "ok" },
      headers: auth("appr_clean"), as: :json

    assert_response :success
  end

  test "the approver can return the record for correction" do
    approver("Anurag ", " Patel", "ret")
    jj = send_for_approval("ret")

    patch "/api/v1/jeevika-jankars/#{jj.id}/return", params: { remarks: "fix" },
      headers: auth("appr_ret"), as: :json

    assert_response :success
  end

  # Collapsing spaces must not let anyone else in.
  test "another user still cannot approve" do
    approver("Anurag ", " Patel", "other")
    User.create!(first_name: "Someone", last_name: "Else", user_name: "appr_outsider",
      email: "outsider@example.com", mobile_no: "9879000099", password: "secret",
      user_type: "admin", status: "Active", stakeholder: "PAPL", role: "Admin")
    jj = send_for_approval("other")

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "ok" },
      headers: auth("appr_outsider"), as: :json

    assert_response :forbidden
    assert_includes response.parsed_body["message"], "not pending for your approval"
  end

  # "Not pending for your approval" on its own left nowhere to look, so the
  # refusal now names the two people being compared.
  test "a refusal names who it is waiting on and who you are" do
    approver("Anurag ", " Patel", "why")
    User.create!(first_name: "Some", last_name: "Admin", user_name: "appr_why_admin",
      email: "why_admin@example.com", mobile_no: "9879000077", password: "secret",
      user_type: "admin", status: "Active", stakeholder: "PAPL", role: "Admin")
    jj = send_for_approval("why")

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "ok" },
      headers: auth("appr_why_admin"), as: :json

    assert_response :forbidden
    body = response.parsed_body
    assert_equal APPROVER, body["pending_at"]
    assert_equal "Some Admin", body["signed_in_as"]
    assert_includes body["message"], "waiting on"
  end

  test "a record that was never sent reports its status instead" do
    approver("Anurag", "Patel", "nosend")
    registrar = User.create!(first_name: "Reg", last_name: "User", user_name: "reg_nosend",
      email: "reg_nosend@example.com", mobile_no: "9879000088", password: "secret",
      user_type: "User", status: "Active", stakeholder: "PAPL", role: "Data Entry")
    jj = Vrp.create!(name: "Unsent", father_husband_name: "T", gender: :female,
      date_of_birth: Date.new(2012, 10, 4), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1", bank_name: "B", branch: "Br",
      ifsc_code: "SBIN0001234", address: "A", mobile_no: "9879000089",
      email: "unsent@example.com", experience_in_years: 1, office_detail_id: 0,
      to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 10, user_name: "unsent_jj",
      password: "secret", created_by_id: registrar.id, created_by_type: "User")

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "ok" },
      headers: auth("appr_nosend"), as: :json

    assert_response :forbidden
    assert_includes response.parsed_body["message"], "no approval step waiting"
    assert_equal 10, response.parsed_body["jeevika_jankar_status"]
  end

  def approver(first, last, tag)
    ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Registration", "stakeholder_name" => "PAPL",
      "approval_level" => "First Approval", "approver_approved_by" => APPROVER,
      "status" => "Active" })
    User.create!(first_name: first, last_name: last, user_name: "appr_#{tag}",
      email: "appr_#{tag}@example.com", mobile_no: "98790#{tag.bytes.sum.to_s.rjust(5, '0')}",
      password: "secret", user_type: "User", status: "Active",
      stakeholder: "PAPL", role: "PMC-Oprection")
  end

  def send_for_approval(tag)
    registrar = User.create!(first_name: "Reg", last_name: "User", user_name: "reg_#{tag}",
      email: "reg_#{tag}@example.com", mobile_no: "98791#{tag.bytes.sum.to_s.rjust(5, '0')}",
      password: "secret", user_type: "User", status: "Active",
      stakeholder: "PAPL", role: "Data Entry")
    jj = Vrp.create!(name: "Testingasa #{tag}", father_husband_name: "T", gender: :female,
      date_of_birth: Date.new(2012, 10, 4), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "5888556685588", bank_name: "B", branch: "Br",
      ifsc_code: "SBIN0001234", address: "A",
      mobile_no: "98792#{tag.bytes.sum.to_s.rjust(5, '0')}", email: "t_#{tag}@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      status: 10, user_name: "tjj_#{tag}", password: "secret",
      created_by_id: registrar.id, created_by_type: "User")
    patch "/api/v1/jeevika-jankars/#{jj.id}/send_for_approval", headers: auth("reg_#{tag}"), as: :json
    assert_response :success, "setup: send for approval failed"
    jj
  end

  def auth(login)
    post api_v1_login_path, params: { login: login, password: "secret" }, as: :json
    assert_response :success
    { "Authorization" => "Bearer #{response.parsed_body['token']}" }
  end
end
