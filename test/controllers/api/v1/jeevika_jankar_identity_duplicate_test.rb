require "test_helper"

# The Jeevika Jankar APIs batch the creator lookups that build the
# "registered by" label and feed approval matching. users.email and
# users.mobile_no have no unique index, so one value can match several
# accounts, and the batch has to settle on the same one the per-record
# User.find_by fallback would - the lowest id.
class Api::V1::JeevikaJankarIdentityDuplicateTest < ActionDispatch::IntegrationTest
  def make_user(suffix, email:, mobile:, first_name:)
    User.create!(
      first_name: first_name, last_name: suffix, user_name: "api_dup_#{suffix}",
      email: email, mobile_no: mobile, password: "secret",
      role: "Agronomist", stakeholder: "ASA", stakeholder_role: "Agronomist",
      user_type: "user", status: "Active"
    )
  end

  def make_vrp(email:, mobile:)
    Vrp.create!(
      name: "Dup Creator JJ", father_husband_name: "T", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "661234567890", account_no: "6612345678", bank_name: "B",
      branch: "T", ifsc_code: "TEST0123456", address: "A",
      mobile_no: mobile, email: email, experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, user_name: "dup_creator_jj", password: "secret",
      status: 10
    )
  end

  def admin_token
    admin = User.create!(
      first_name: "Api", last_name: "Admin", user_name: "api_dup_admin",
      email: "api_dup_admin@example.com", mobile_no: "9700000001",
      password: "secret", user_type: "admin", status: "Active"
    )
    ApiAuthToken.encode(admin)
  end

  test "batched creator lookup settles on the lowest id when an email repeats" do
    first = make_user("email_a", email: "dupapi@example.com", mobile: "9700000002", first_name: "Earlier")
    second = make_user("email_b", email: "dupapi@example.com", mobile: "9700000003", first_name: "Later")
    assert_operator first.id, :<, second.id

    vrp = make_vrp(email: "dupapi@example.com", mobile: "9700000099")
    token = admin_token

    get "/api/v1/jeevika-jankars", params: { per_page: 100 },
      headers: { "Authorization" => "Bearer #{token}" }, as: :json
    assert_response :success

    row = response.parsed_body["jeevika_jankars"].find { |r| r["id"] == vrp.id }
    assert row, "the Jeevika Jankar should be listed"

    # Whatever the label is built from, it must come from the lower-id account.
    assert_not_includes row.to_json, "Later",
      "the batched lookup used the higher-id duplicate account; the per-record " \
      "User.find_by fallback resolves the lower-id one"
  end

  test "batched creator lookup settles on the lowest id when a mobile number repeats" do
    first = make_user("mob_a", email: "dupmob_a@example.com", mobile: "9700000004", first_name: "Earlier")
    second = make_user("mob_b", email: "dupmob_b@example.com", mobile: "9700000004", first_name: "Later")
    assert_operator first.id, :<, second.id

    vrp = make_vrp(email: "nomatch_dup@example.com", mobile: "9700000004")
    token = admin_token

    get "/api/v1/jeevika-jankars", params: { per_page: 100 },
      headers: { "Authorization" => "Bearer #{token}" }, as: :json
    assert_response :success

    row = response.parsed_body["jeevika_jankars"].find { |r| r["id"] == vrp.id }
    assert row, "the Jeevika Jankar should be listed"
    assert_not_includes row.to_json, "Later",
      "the batched lookup used the higher-id duplicate account"
  end

  test "the preloaded lookup agrees with the per-record fallback it replaces" do
    first = make_user("agree_a", email: "agree@example.com", mobile: "9700000005", first_name: "Earlier")
    make_user("agree_b", email: "agree@example.com", mobile: "9700000006", first_name: "Later")
    vrp = make_vrp(email: "agree@example.com", mobile: "9700000098")

    controller = Api::V1::JeevikaJankarsController.new

    # Per-record path: no batch has run, so the cache miss goes to find_by.
    fallback = controller.send(:cached_vrp_creator_user_by, email: "agree@example.com")

    batched_controller = Api::V1::JeevikaJankarsController.new
    batched_controller.send(:preload_vrp_creator_identity_lookups!, [vrp])
    batched = batched_controller.send(:cached_vrp_creator_user_by, email: "agree@example.com")

    assert_equal fallback.id, batched.id
    assert_equal first.id, batched.id
  end
end
