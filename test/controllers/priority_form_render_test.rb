require "test_helper"

class PriorityFormRenderTest < ActionDispatch::IntegrationTest
  test "user and JJ forms retain complete location options on cold and warm authenticated renders" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    120.times do |i|
      ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => format("Priority State %03d", i) })
    end
    admin = User.create!(user_name: "priority_render_admin", first_name: "Priority Admin", password: "secret",
      user_type: "admin", status: "Active")
    post login_path, params: { login: admin.user_name, password: "secret" }
    [new_user_path, new_vrp_path].each do |path|
      get path
      assert_response :success
      selector = "[data-location-level='state'] option"
      before = css_select(selector).map(&:to_html)
      assert_operator before.size, :>=, 120
      assert_select "[data-location-level='state'] option", text: "Priority State 001", count: 1
      get path
      assert_response :success
      assert_equal before, css_select(selector).map(&:to_html)
      assert_select "[data-location-form][data-location-map]", minimum: 1
    end
  ensure
    Rails.cache = original_cache
  end
end
