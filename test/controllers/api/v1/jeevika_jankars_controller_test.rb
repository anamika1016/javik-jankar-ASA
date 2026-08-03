require "test_helper"

class Api::V1::JeevikaJankarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_admin_user(user_name: "api_jj_admin", password: "secret")
    @token = api_login_token(login: "api_jj_admin", password: "secret")
  end

  test "list requires auth" do
    get "/api/v1/jeevika-jankars", as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
  end

  test "list returns jeevika jankars for authenticated user" do
    vrp = create_vrp(name: "List JJ", user_name: "list_jj_1", created_by_id: @user.id, status: 10)

    get "/api/v1/jeevika-jankars", headers: auth_headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["jeevika_jankars"].is_a?(Array)
    assert body["jeevika_jankars"].any? { |row| row["id"] == vrp.id }
    assert_equal "Submitted", body["jeevika_jankars"].find { |row| row["id"] == vrp.id }["status_label"]
  end

  test "registration creates jeevika jankar with status 10" do
    payload = registration_payload(user_name: "new_jj_user")

    assert_difference("Vrp.count", 1) do
      post "/api/v1/jeevika-jankars",
        params: payload,
        headers: auth_headers,
        as: :json
    end

    assert_response :created
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal 10, body.dig("jeevika_jankar", "status")
    assert_equal "new_jj_user", body.dig("jeevika_jankar", "user_name")
    assert_equal "Submitted", body.dig("jeevika_jankar", "status_label")

    vrp = Vrp.find(body.dig("jeevika_jankar", "id"))
    assert_equal @user.id, vrp.created_by_id
    assert_equal "User", vrp.created_by_type
    assert_equal 10, vrp.status
  end

  test "registration preserves module record creator when ids collide" do
    module_user = ModuleRecord.create!(
      module_slug: "new-user",
      data: {
        "first_name" => "Android",
        "last_name" => "Registrar",
        "user_name" => "android_registrar",
        "password" => "secret",
        "status" => "Active"
      }
    )
    User.create!(
      id: module_user.id,
      first_name: "Wrong",
      last_name: "User",
      email: "wrong_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_name: "wrong_user",
      user_type: "user",
      status: "Active"
    )
    token = ApiAuthToken.encode(module_user)

    post "/api/v1/jeevika-jankars",
      params: registration_payload(user_name: "module_created_jj"),
      headers: { "Authorization" => "Bearer #{token}" },
      as: :json

    assert_response :created
    vrp = Vrp.find(response.parsed_body.dig("jeevika_jankar", "id"))
    assert_equal module_user.id, vrp.created_by_id
    assert_equal "ModuleRecord", vrp.created_by_type
    assert_equal "Android Registrar", response.parsed_body.dig("jeevika_jankar", "registered_by")
  end

  test "registration rejects mismatched password" do
    payload = registration_payload(user_name: "bad_pass_jj")
    payload[:confirmed_password] = "different"

    assert_no_difference("Vrp.count") do
      post "/api/v1/jeevika-jankars",
        params: payload,
        headers: auth_headers,
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["success"]
  end

  test "form options returns dropdown data" do
    get "/api/v1/jeevika-jankars/form-options", headers: auth_headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["options"].key?("vrp_types")
    assert body["options"].key?("genders")
    assert body["options"].key?("states")
  end

  test "show returns detail for visible record" do
    vrp = create_vrp(name: "Show JJ", user_name: "show_jj_1", created_by_id: @user.id, status: 10)

    get "/api/v1/jeevika-jankars/#{vrp.id}", headers: auth_headers, as: :json

    assert_response :success
    assert_equal vrp.id, response.parsed_body.dig("jeevika_jankar", "id")
  end

  test "update edits manageable jeevika jankar without clearing omitted fields" do
    vrp = create_vrp(
      name: "Old JJ Name",
      user_name: "editable_jj",
      email: "keep@example.com",
      created_by_id: @user.id,
      status: 10
    )

    patch "/api/v1/jeevika-jankars/#{vrp.id}",
      params: { name: "Updated JJ Name", address: "Updated Address" },
      headers: auth_headers,
      as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_equal "Updated JJ Name", response.parsed_body.dig("jeevika_jankar", "name")
    assert_equal "keep@example.com", vrp.reload.email
    assert_equal "secret", vrp.password
  end

  test "update rejects mismatched password confirmation" do
    vrp = create_vrp(user_name: "password_edit_jj", created_by_id: @user.id, status: 10)

    patch "/api/v1/jeevika-jankars/#{vrp.id}",
      params: { password: "new-secret", confirmed_password: "different" },
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
    assert_equal "secret", vrp.reload.password
  end

  test "web vrps index still works after api addition" do
    post login_path, params: { login: "api_jj_admin", password: "secret" }
    get vrps_path

    assert_response :success
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
      last_name: "Admin",
      email: "api_jj_admin_#{SecureRandom.hex(3)}@example.com",
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

  def registration_payload(overrides = {})
    {
      name: "Registered JJ",
      father_husband_name: "Father Name",
      gender: "male",
      date_of_birth: "1992-05-10",
      date_of_joining: Date.current.to_s,
      aadhar_no: "123456789012",
      account_no: "9988776655",
      bank_name: "SBI",
      branch: "Main",
      ifsc_code: "SBIN0001234",
      address: "Village Address",
      mobile_no: "9876543211",
      email: "reg#{SecureRandom.hex(3)}@example.com",
      experience_in_years: 2,
      user_name: "reg_jj_user",
      password: "secret123",
      confirmed_password: "secret123",
      vrp_type_ids: [ 1 ],
      gram_panchayat_ids: [ 1 ],
      village_ids: [ 1 ],
      state_id: 1,
      district_id: 1,
      block_id: 1,
      gram_panchayat_id: 1,
      village_id: 1
    }.merge(overrides)
  end
end
