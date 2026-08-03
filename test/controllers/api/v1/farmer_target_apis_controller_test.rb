require "test_helper"

class Api::V1::FarmerTargetApisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_admin_user(user_name: "api_farmer_admin", password: "secret")
    @token = api_login_token(login: "api_farmer_admin", password: "secret")
  end

  test "farmer training list requires auth" do
    get "/api/v1/farmer-trainings", as: :json
    assert_response :unauthorized
  end

  test "farmer training form data requires auth" do
    get "/api/v1/farmer-trainings/form-data", as: :json

    assert_response :unauthorized
  end

  test "farmer training farmer list requires auth" do
    get "/api/v1/farmer-trainings/farmers", as: :json

    assert_response :unauthorized
  end

  test "farmer training months require auth" do
    get "/api/v1/farmer-trainings/months", as: :json

    assert_response :unauthorized
  end

  test "mapped farmer list requires auth" do
    get "/api/v1/farmer-trainings/mapped-farmers", as: :json

    assert_response :unauthorized
  end

  test "farmer training list and form options work" do
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "July",
        "ics_block" => "ICS-1",
        "gram_name" => "Village 1",
        "trainer_name" => "Trainer",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/farmer-trainings", headers: auth_headers, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["farmer_trainings"].is_a?(Array)
    assert body["count"] >= 1

    get "/api/v1/farmer-trainings/form-options", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["options"].key?("target_mappings")
    assert response.parsed_body["options"].key?("autofill")
  end

  test "seed distribution list and form options work" do
    ModuleRecord.create!(
      module_slug: "seed-distribution-target",
      data: {
        "month" => "July",
        "ics" => "ICS-1",
        "village" => "Village 1",
        "jeevika_jankar_name" => "JJ One",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/seed-distribution-targets", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["seed_distribution_targets"].is_a?(Array)

    get "/api/v1/seed-distribution-targets/form-options", headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body["options"].key?("target_mappings")
    assert response.parsed_body["options"].key?("autofill")
  end

  test "papl360 list and form options work" do
    ModuleRecord.create!(
      module_slug: "papl360-target",
      data: {
        "month" => "July",
        "ics" => "ICS-1",
        "village" => "Village 1",
        "jeevika_jankar_name" => "JJ One",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/papl360-targets", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["papl360_targets"].is_a?(Array)

    get "/api/v1/papl360-targets/form-options", headers: auth_headers, as: :json
    assert_response :success
  end

  test "add farmer form list create and form options work" do
    vrp = create_vrp(user_name: "add_farmer_vrp", name: "Add Farmer VRP")
    mapping = TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      month_name: "July",
      main_activity_name: "New Farmer",
      activity_name: "Enrollment",
      target_quantity: 5,
      afl_ids: []
    )

    get "/api/v1/add-farmer-forms/form-options", headers: auth_headers, as: :json
    assert_response :success
    options = response.parsed_body["options"]
    assert options["mappings"].any? { |row| row["id"] == mapping.id.to_s }

    post "/api/v1/add-farmer-forms",
      params: {
        target_mapping_id: mapping.id.to_s,
        no_farmer: 3
      },
      headers: auth_headers,
      as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal "3", body.dig("add_farmer_form", "data", "no_farmer")
    assert_equal mapping.id.to_s, body.dig("add_farmer_form", "data", "target_mapping_id")

    get "/api/v1/add-farmer-forms", headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body["add_farmer_forms"].any?
  end

  test "web modules path still works after api addition" do
    post login_path, params: { login: "api_farmer_admin", password: "secret" }
    get "/modules/training-form-list"
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
      email: "api_farmer_admin_#{SecureRandom.hex(3)}@example.com",
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
      status: 55,
      password: "secret"
    }

    Vrp.create!(defaults.merge(attributes))
  end
end
