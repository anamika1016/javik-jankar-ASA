require "test_helper"

class Api::V1::SidebarMenusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_admin_user
    @token = ApiAuthToken.encode(@user)
  end

  test "sidebar menus require authentication" do
    get "/api/v1/sidebar-menus", as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
  end

  test "sidebar menus return access-control-backed sections" do
    get "/api/v1/sidebar-menus", headers: auth_headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal @user.id, body.dig("user", "id")
    assert body["sidebar_sections"].is_a?(Array)
    assert body["sidebar_sections"].all? { |section| section["menus"].is_a?(Array) }
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def create_admin_user
    User.create!(
      first_name: "Sidebar",
      last_name: "Admin",
      email: "sidebar_admin_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_name: "sidebar_admin_#{SecureRandom.hex(3)}",
      user_type: "admin",
      status: "Active",
      stakeholder: "PAPL",
      role: "Admin"
    )
  end
end
