require "test_helper"

class Api::V1::JeevikaJankarApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_admin_user(user_name: "api_jj_approver", password: "secret")
    @token = api_login_token(login: "api_jj_approver", password: "secret")
  end

  test "approval queue requires auth" do
    get "/api/v1/jeevika-jankars/approvals", as: :json

    assert_response :unauthorized
  end

  test "approval queue returns success payload" do
    get "/api/v1/jeevika-jankars/approvals", headers: auth_headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["approvals"].is_a?(Array)
  end

  test "approve rejects when not pending for user" do
    vrp = create_vrp(name: "No Queue JJ", user_name: "no_queue_jj", created_by_id: @user.id, status: 10)

    patch "/api/v1/jeevika-jankars/#{vrp.id}/approve",
      params: { remarks: "ok" },
      headers: auth_headers,
      as: :json

    assert_response :forbidden
    assert_equal false, response.parsed_body["success"]
  end

  test "return rejects when not pending for user" do
    vrp = create_vrp(name: "No Return Queue JJ", user_name: "no_return_queue_jj", created_by_id: @user.id, status: 10)

    patch "/api/v1/jeevika-jankars/#{vrp.id}/return",
      params: { remarks: "Please correct the details" },
      headers: auth_headers,
      as: :json

    assert_response :forbidden
    assert_equal false, response.parsed_body["success"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def api_login_token(login:, password:)
    post api_v1_login_path, params: { login: login, password: password }, as: :json
    assert_response :success
    response.parsed_body["token"]
  end

  def create_admin_user(attributes = {})
    defaults = {
      first_name: "Api",
      last_name: "Approver",
      email: "api_jj_approver_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_type: "admin",
      status: "Active",
      stakeholder: "PAPL",
      role: "Admin"
    }
    User.create!(defaults.merge(attributes))
  end

  def create_vrp(attributes = {})
    defaults = {
      name: "Test JJ",
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
      email: "jj#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [ 1 ],
      gram_panchayat_ids: [ 1 ],
      village_ids: [ 1 ],
      is_active: true,
      is_deleted: false,
      status: 10,
      password: "secret"
    }

    Vrp.create!(defaults.merge(attributes))
  end
end
