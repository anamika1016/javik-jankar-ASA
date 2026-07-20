require "test_helper"

class Api::V1::JeevikaJankarMastersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      first_name: "Master", last_name: "Admin", email: "master_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}", password: "secret",
      user_name: "master_#{SecureRandom.hex(3)}", user_type: "admin", status: "Active",
      stakeholder: "PAPL", role: "Admin"
    )
    post api_v1_login_path, params: { login: @user.user_name, password: "secret" }, as: :json
    @headers = { "Authorization" => "Bearer #{response.parsed_body['token']}" }
  end

  test "master APIs require authentication" do
    get "/api/v1/jeevika-jankar-masters/states", as: :json
    assert_response :unauthorized
  end

  test "state list returns active records" do
    active = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Bihar", "state_code" => "10", "status" => "Active" })
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Hidden", "status" => "Inactive" })

    get "/api/v1/jeevika-jankar-masters/states", headers: @headers, as: :json

    assert_response :success
    assert_equal [ active.id ], response.parsed_body["states"].map { |row| row["id"] }
  end

  test "district list supports state filter" do
    ModuleRecord.create!(module_slug: "district-master", data: { "state" => "Bihar", "district_name" => "Patna", "status" => "Active" })
    ModuleRecord.create!(module_slug: "district-master", data: { "state" => "Jharkhand", "district_name" => "Ranchi", "status" => "Active" })

    get "/api/v1/jeevika-jankar-masters/districts", params: { state: "Bihar" }, headers: @headers, as: :json

    assert_response :success
    assert_equal [ "Patna" ], response.parsed_body["districts"].map { |row| row["district_name"] }
  end

  test "creates jeevika jankar type without module web action" do
    assert_difference("ModuleRecord.where(module_slug: 'add-vrp-type').count", 1) do
      post "/api/v1/jeevika-jankar-types",
        params: { jeevika_jankar_type_name: "Community Mobilizer" }, headers: @headers, as: :json
    end

    assert_response :created
    assert_equal "Community Mobilizer", response.parsed_body.dig("jeevika_jankar_type", "jeevika_jankar_type_name")
  end
end
