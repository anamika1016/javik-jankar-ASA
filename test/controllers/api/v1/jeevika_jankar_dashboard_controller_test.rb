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
end
