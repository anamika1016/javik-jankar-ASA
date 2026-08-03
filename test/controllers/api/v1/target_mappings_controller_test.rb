require "test_helper"

class Api::V1::TargetMappingsControllerTest < ActionDispatch::IntegrationTest
  test "recent target mappings require authentication" do
    get "/api/v1/target-mappings/recent", as: :json

    assert_response :unauthorized
  end
end
