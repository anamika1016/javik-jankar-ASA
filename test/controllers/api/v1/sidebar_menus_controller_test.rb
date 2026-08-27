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

  test "bill access does not expose payment menus without separate access" do
    user = create_limited_user
    token = ApiAuthToken.encode(user)
    create_access_record(user, "Bill List")

    get "/api/v1/sidebar-menus", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    menu_names = response.parsed_body["sidebar_sections"].flat_map { |section| section["menus"].map { |menu| menu["name"] } }
    assert_includes menu_names, "Bill List"
    refute_includes menu_names, "Payment List"
    refute_includes menu_names, "Payment List Detail"
    refute_includes menu_names, "Completed Payment List"

    create_access_record(user, "Payment List")
    get "/api/v1/sidebar-menus", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    menu_names = response.parsed_body["sidebar_sections"].flat_map { |section| section["menus"].map { |menu| menu["name"] } }
    assert_includes menu_names, "Bill List"
    assert_includes menu_names, "Payment List"
    refute_includes menu_names, "Payment List Detail"
    refute_includes menu_names, "Completed Payment List"
  end

  test "farmer target access does not expose sibling menus without separate access" do
    user = create_limited_user
    token = ApiAuthToken.encode(user)
    create_access_record(user, "Farmer Training Form")

    get "/api/v1/sidebar-menus", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    menu_names = response.parsed_body["sidebar_sections"].flat_map { |section| section["menus"].map { |menu| menu["name"] } }
    assert_includes menu_names, "Farmer Training Form"
    refute_includes menu_names, "Farmer Training Form List"
    refute_includes menu_names, "Farmer Participation Report"
    refute_includes menu_names, "Seed Distribution Target"
    refute_includes menu_names, "Seed Distribution Target List"
    refute_includes menu_names, "PAPL360 Target"
    refute_includes menu_names, "PAPL360 Target List"
    refute_includes menu_names, "Add Farmer Form"
  end

  test "farmer farm information access does not expose sibling menus without separate access" do
    user = create_limited_user
    token = ApiAuthToken.encode(user)
    create_access_record(user, "Farmer Farm Information")

    get "/api/v1/sidebar-menus", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    menu_names = response.parsed_body["sidebar_sections"].flat_map { |section| section["menus"].map { |menu| menu["name"] } }
    assert_includes menu_names, "Farmer Farm Information"
    refute_includes menu_names, "All Basic Detail List"
    refute_includes menu_names, "Farm Map (lat long gps)"
    refute_includes menu_names, "Crop Map Session Wise Farm Map (lat long gps)"
    refute_includes menu_names, "Application Format for Exit of Farmer from ICS"
  end

  test "blank can view does not grant menu access" do
    user = create_limited_user
    token = ApiAuthToken.encode(user)
    create_access_record(user, "Payment List", can_view: "")

    get "/api/v1/sidebar-menus", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    menu_names = response.parsed_body["sidebar_sections"].flat_map { |section| section["menus"].map { |menu| menu["name"] } }
    refute_includes menu_names, "Payment List"
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

  def create_limited_user
    User.create!(
      first_name: "Sidebar",
      last_name: "Limited",
      email: "sidebar_limited_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "8#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_name: "sidebar_limited_#{SecureRandom.hex(3)}",
      user_type: "user",
      status: "Active",
      stakeholder: "PAPL",
      role: "Finance"
    )
  end

  def create_access_record(user, sub_module_name, can_view: "Yes")
    ModuleRecord.create!(
      module_slug: "access-control",
      data: {
        "stakeholder_name" => user.stakeholder,
        "role" => user.role,
        "sub_module_name" => sub_module_name,
        "can_view" => can_view,
        "status" => "Active"
      }
    )
  end
end
