require "test_helper"

class Api::V1::UnitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = SecureRandom.hex(3)
    ["Kg#{@tag}", "Bag#{@tag}"].each { |name| ModuleRecord.create!(module_slug: "unit-master", data: { "unit_name" => name, "status" => "Active" }) }
    ModuleRecord.create!(module_slug: "unit-master", data: { "unit_name" => "Old#{@tag}", "status" => "Inactive" })
    @user = User.create!(user_name: "unit_api_#{@tag}", password: "secret", first_name: "U", user_type: "admin", status: "Active")
  end

  test "needs a login" do
    get "/api/v1/units"
    assert_response :unauthorized
  end

  test "lists active units A-Z with id and name" do
    get "/api/v1/units", headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(@user)}" }
    assert_response :success
    names = response.parsed_body["units"].map { |unit| unit["name"] }.select { |name| name.end_with?(@tag) }
    assert_equal ["Bag#{@tag}", "Kg#{@tag}"], names
    assert response.parsed_body["units"].all? { |unit| unit["id"].is_a?(Integer) }
  end
end
