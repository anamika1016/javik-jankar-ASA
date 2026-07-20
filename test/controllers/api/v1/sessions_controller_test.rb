require "test_helper"

class Api::V1::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "api login returns token and user for valid vrp credentials" do
    vrp = create_vrp(user_name: "api_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { login: "api_vrp", password: "secret" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["token"].present?
    assert_equal vrp.id, body.dig("user", "id")
    assert_equal "Vrp", body.dig("user", "record_type")
    assert_equal "api_vrp", body.dig("user", "username")
  end

  test "api login accepts username alias" do
    create_vrp(user_name: "api_username_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { username: "api_username_vrp", password: "secret" }, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
  end

  test "api login rejects invalid credentials" do
    create_vrp(user_name: "api_bad_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { login: "api_bad_vrp", password: "wrong" }, as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
    assert_equal "Invalid username or password.", response.parsed_body["message"]
  end

  test "api login blocks vrp without agreement" do
    create_vrp(user_name: "api_unsigned_vrp", password: "secret")

    post api_v1_login_path, params: { login: "api_unsigned_vrp", password: "secret" }, as: :json

    assert_response :forbidden
    assert_equal false, response.parsed_body["success"]
    assert_equal "agreement_required", response.parsed_body["error"]
  end

  test "api me returns current user with bearer token" do
    vrp = create_vrp(user_name: "api_me_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { login: "api_me_vrp", password: "secret" }, as: :json
    token = response.parsed_body["token"]

    get api_v1_me_path, headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_equal vrp.id, response.parsed_body.dig("user", "id")
  end

  test "api me rejects missing token" do
    get api_v1_me_path, as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
  end

  test "web login still works after api addition" do
    create_vrp(user_name: "web_still_works", password: "secret", agreement_accepted_at: Time.current)

    post login_path, params: { login: "web_still_works", password: "secret" }

    assert_redirected_to dashboard_path
  end

  private

  def create_vrp(attributes = {})
    defaults = {
      name: "Test VRP",
      father_husband_name: "Test Father",
      gender: :male,
      date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current,
      aadhar_no: "123456789012",
      account_no: "1234567890",
      bank_name: "Test Bank",
      branch: "Test Branch",
      ifsc_code: "TEST0123456",
      address: "Test Address",
      mobile_no: "9876543210",
      email: "vrp#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      is_active: true,
      is_deleted: false
    }

    Vrp.create!(defaults.merge(attributes))
  end
end
