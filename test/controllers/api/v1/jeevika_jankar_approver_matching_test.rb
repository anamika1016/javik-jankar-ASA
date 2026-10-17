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

  test "assigned approver sees the record in JJ list and detail" do
    approver("Anurag ", " Patel", "visible")
    jj = send_for_approval("visible")
    headers = auth("appr_visible")

    get "/api/v1/jeevika-jankars", params: { per_page: 1000 }, headers: headers, as: :json

    assert_response :success
    assert_includes response.parsed_body["jeevika_jankars"].map { |row| row["id"] }, jj.id

    get "/api/v1/jeevika-jankars/#{jj.id}", headers: headers, as: :json

    assert_response :success
    assert_equal jj.id, response.parsed_body.dig("jeevika_jankar", "id")
  end

  test "saved pending approver remains visible when approval master later changes" do
    approver("Anurag", "Patel", "persisted")
    jj = send_for_approval("persisted")
    ModuleRecord.where(module_slug: "approval-master").delete_all
    history = ModuleRecord.where(module_slug: "vrp-approval-history").order(:created_at).last
    history.update!(data: history.data.merge(
      "status" => "Pending at #{APPROVER}",
      "remarks" => "Pending at #{APPROVER}"
    ))

    get "/api/v1/jeevika-jankars", params: { per_page: 1000 },
      headers: auth("appr_persisted"), as: :json

    assert_response :success
    assert_includes response.parsed_body["jeevika_jankars"].map { |row| row["id"] }, jj.id
  end

  test "record moves from first approver into Anurag approval queue and can be approved" do
    first = User.create!(
      first_name: "Soumen", last_name: "Day", user_name: "appr_first",
      email: "appr_first@example.com", mobile_no: "9879000111", password: "secret",
      user_type: "User", status: "Active", stakeholder: "PAPL", role: "PMC-Oprection"
    )
    anurag = User.create!(
      first_name: "Anurag", last_name: "Patel", user_name: "appr_anurag_queue",
      email: "appr_anurag_queue@example.com", mobile_no: "9879000222", password: "secret",
      user_type: "User", status: "Active", stakeholder: "PAPL", role: "PMC-Oprection"
    )
    ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Registration", "stakeholder_name" => "PAPL",
      "approval_level" => "First Approval", "approver_approved_by" => "Soumen Day (PMC-Oprection)",
      "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Registration", "stakeholder_name" => "PAPL",
      "approval_level" => "Second Approval", "approver_approved_by" => APPROVER,
      "status" => "Active"
    })
    jj = send_for_approval("two_step")

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "first done" },
      headers: auth(first.user_name), as: :json
    assert_response :success
    assert_equal 31, jj.reload.status.to_i
    assert_includes response.parsed_body["message"], "Anurag Patel"

    headers = auth(anurag.user_name)
    get "/api/v1/jeevika-jankars/approvals", headers: headers, as: :json
    assert_response :success
    assert_includes response.parsed_body["approvals"].map { |row| row["id"] }, jj.id
    queue_row = response.parsed_body["approvals"].find { |row| row["id"] == jj.id }
    assert_equal true, queue_row["can_act"]
    assert_includes queue_row["status_label"], "Anurag Patel"

    get "/api/v1/jeevika-jankars", params: { per_page: 1000 }, headers: headers, as: :json
    assert_response :success
    assert_includes response.parsed_body["jeevika_jankars"].map { |row| row["id"] }, jj.id

    patch "/api/v1/jeevika-jankars/#{jj.id}/approve", params: { remarks: "approved" },
      headers: headers, as: :json
    assert_response :success
    assert_equal 55, jj.reload.status.to_i
  end

  test "status sequence dynamically puts JJ in Anurag queue when creator channel lookup is missing" do
    approver("Anurag", "Patel", "sequence")
    registrar = User.create!(
      first_name: "Legacy", last_name: "Registrar", user_name: "legacy_sequence_registrar",
      email: "legacy_sequence_registrar@example.com", mobile_no: "9879000333",
      password: "secret", user_type: "User", status: "Active",
      stakeholder: "Different Stakeholder", role: "Data Entry"
    )
    jj = Vrp.create!(name: "Sequence JJ", father_husband_name: "T", gender: :female,
      date_of_birth: Date.new(2012, 10, 4), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1", bank_name: "B", branch: "Br",
      ifsc_code: "SBIN0001234", address: "A", mobile_no: "9879000444",
      email: "sequence_jj@example.com", experience_in_years: 1, office_detail_id: 0,
      to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 30, user_name: "sequence_jj",
      password: "secret", created_by_id: registrar.id, created_by_type: "User")

    headers = auth("appr_sequence")
    get "/api/v1/jeevika-jankars/approvals", headers: headers, as: :json
    assert_response :success
    assert_includes response.parsed_body["approvals"].map { |row| row["id"] }, jj.id

    get "/api/v1/jeevika-jankars", params: { per_page: 1000 }, headers: headers, as: :json
    assert_response :success
    assert_includes response.parsed_body["jeevika_jankars"].map { |row| row["id"] }, jj.id
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
    assert_equal 10, jj.reload.status.to_i
    assert_equal 10, response.parsed_body.dig("jeevika_jankar", "status").to_i
    history = ModuleRecord.where(module_slug: "vrp-approval-history").order(:created_at).select do |record|
      record.data["vrp_id"].to_i == jj.id
    end
    assert_equal "Returned", history.last.data["action"]
    assert_equal "fix", history.last.data["remarks"]
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
