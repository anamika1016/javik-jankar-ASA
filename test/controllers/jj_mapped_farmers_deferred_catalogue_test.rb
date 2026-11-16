require "test_helper"

class JjMappedFarmersDeferredCatalogueTest < ActionController::TestCase
  tests TargetMappingsController

  setup do
    @viewer = { "id" => "1", "record_type" => "User", "user_type" => "admin", "username" => "admin" }
    viewer = -> { @viewer }
    @controller.define_singleton_method(:current_app_user) { viewer.call }
    @calls = 0
    bump = -> { @calls += 1 }
    @controller.define_singleton_method(:fetch_external_vrp_users) do
      bump.call
      [{ id: "7", name: "Remote JJ", mobile_no: "9000000007", label: "Remote <JJ> (9000000007)" }]
    end
    @controller.define_singleton_method(:fetch_external_mapped_farmers) do |**_|
      { farmers: [], mapped_villages: [], count: 0 }
    end
  end

  test "initial admin page does not wait for remote catalogue and preserves required picker and direct mobile" do
    get :jj_mapped_farmers
    assert_response :success
    assert_equal 0, @calls
    assert_select 'turbo-frame#jj_api_user_picker[src=?]', jj_user_options_target_mappings_path
    assert_select 'select[name="mobile_no"][required]', 1
    assert_select 'input[name="vrp_mobile"]', 1
    assert_select 'noscript a[href*="load_users=1"]', 1
  end

  test "admin frame returns identical escaped remote option values without the page layout" do
    get :jj_user_options
    assert_response :success
    assert_equal 1, @calls
    assert_select 'turbo-frame#jj_api_user_picker option[value="9000000007"]', text: "Remote <JJ> (9000000007)"
    refute_match(/<html(?:\s|>)/i, response.body)
    assert_select "script", 0
  end

  test "non admin frame request is denied before any remote call" do
    @viewer = { "id" => "1", "record_type" => "User", "user_type" => "User", "username" => "staff" }
    get :jj_user_options
    assert_response :forbidden
    assert_equal 0, @calls
  end

  test "request parameters cannot grant access to the admin catalogue" do
    @viewer = { "id" => "1", "record_type" => "User", "user_type" => "User", "username" => "staff" }
    get :jj_user_options, params: { user_type: "admin", role: "admin", username: "admin", mobile_no: "admin" }
    assert_response :forbidden
    assert_equal 0, @calls
    assert_empty response.body
  end

  test "signed out frame request redirects to login without fetching remote users" do
    @viewer = nil
    get :jj_user_options
    assert_redirected_to login_path
    assert_equal 0, @calls
  end

  test "selected mobile and no-JavaScript fallback preserve synchronous report behavior" do
    get :jj_mapped_farmers, params: { mobile_no: "9000000007" }
    assert_response :success
    assert_equal 1, @calls
    assert_select 'turbo-frame#jj_api_user_picker', 0
    assert_select 'option[value="9000000007"][selected]', 1
    get :jj_mapped_farmers, params: { load_users: "1" }
    assert_response :success
    assert_equal 2, @calls
    assert_select 'turbo-frame#jj_api_user_picker', 0
  end
end
