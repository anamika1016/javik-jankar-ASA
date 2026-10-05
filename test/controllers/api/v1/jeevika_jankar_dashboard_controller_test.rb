require "test_helper"

class Api::V1::JeevikaJankarDashboardControllerTest < ActionDispatch::IntegrationTest
  test "dashboard requires authentication" do
    get "/api/v1/jeevika-jankar-dashboard", as: :json
    assert_response :unauthorized
  end

  test "admin dashboard route is available to authenticated admin" do
    user = User.create!(
      first_name: "Dashboard",
      last_name: "Admin",
      user_name: "dashboard_admin",
      email: "dashboard_admin@example.com",
      mobile_no: "9876500001",
      password: "secret",
      user_type: "admin",
      status: "Active"
    )
    token = ApiAuthToken.encode(user)

    get "/api/v1/jeevika-jankar-dashboard", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    assert_equal "admin", response.parsed_body["dashboard_type"]
    assert response.parsed_body.key?("farmer_training_participation_status")
    assert response.parsed_body.key?("target_dashboard")
    assert response.parsed_body.key?("weekly_activity_target_status")
  end
  test "VRP dashboard computes training progress using authenticated API context" do
    vrp = Vrp.create!(name: "API Progress JJ", father_husband_name: "Test", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "Test Bank",
      branch: "Test", ifsc_code: "TEST0123456", address: "Test", mobile_no: "9876543210",
      email: "api_progress@example.com", experience_in_years: 1, office_detail_id: 0,
      to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, user_name: "api_progress", password: "secret")
    farmer = Afl.create!(fco_id: "FCO1", fco: "FCO One", ics_id: "ICS1", ics_name: "ICS One", farmer_name: "API Farmer", village_id: "V1", village_name: "Village One")
    target = TargetMapping.create!(vrp: vrp, fco_id: "FCO1", fco_name: "FCO One", month_name: "October", main_activity_name: "Farmers' Training",
      activity_name: "Soil", village_id: "V1", village_name: "Village One", ics_id: "ICS1",
      afl_ids: [farmer.id], farmer_count: 1, target_quantity: 1,
      completion_date: Date.new(2026, 10, 31), created_by_type: "User", created_by_id: 1)
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October",
      "target_mapping_ids" => [target.id.to_s], "selected_farmer_ids" => [farmer.id.to_s],
      "main_activity" => "Farmers' Training", "sub_activity" => "Soil",
      "created_by_type" => "Vrp", "created_by_id" => vrp.id.to_s, "vrp_id" => vrp.id.to_s })

    get "/api/v1/jeevika-jankar-dashboard", params: { month: "October" },
      headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(vrp)}" }, as: :json

    assert_response :success
    assert_equal 1, response.parsed_body.dig("cards", "assigned_target")
    assert_equal 1, response.parsed_body.dig("cards", "achieved_target")
    assert_equal 0, response.parsed_body.dig("cards", "pending_target")
  end

end
