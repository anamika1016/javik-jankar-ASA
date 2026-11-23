require "test_helper"

class DashboardSwitchSpeedTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "switch_cache_admin", password: "secret", first_name: "Cache Owner", user_type: "admin", status: "Active")
    @staff = User.create!(user_name: "switch_cache_staff", password: "secret", first_name: "Office Viewer", user_type: "User", role: "Agronomist", office_name: "FCO-Bhawanipatna", status: "Active")
    ModuleRecord.create!(module_slug: "access-control", data: { "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active" })
    @farmer = Afl.create!(farmer_name: "Cache farmer", fco_id: "995", fco: "Bhawanipatna", ics_id: "ICS-A", ics_name: "ICS A", village_id: "V-A", village_name: "Village A", tracenet_no: "CACHE-A")
    @filters = { entry_mode: "ics_wise", month: "", main_activity: "" }
    post login_path, params: { login: @admin.user_name, password: "secret" }
    get dashboard_path, params: @filters # Consume the login flash without caching it.
  end

  test "warm mode clicks reuse rendered responses without reloading targets" do
    get dashboard_path, params: @filters, headers: { "X-Dashboard-Warm" => "1" }
    assert_equal "miss", response.headers["X-Dashboard-Cache"]
    target_loads = []
    callback = ->(*args) { target_loads << args.last[:sql] if args.last[:name] == "TargetMapping Load" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get dashboard_path, params: @filters
    end
    assert_response :success
    assert_equal "hit", response.headers["X-Dashboard-Cache"]
    assert_empty target_loads
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "1"
    assert_select ".dashboard-view-switch-item[data-dashboard-mode-link][data-turbo-prefetch=true]", 3
  end

  test "saved changes and deletions immediately invalidate a warm response" do
    2.times { get dashboard_path, params: @filters }
    assert_equal "hit", response.headers["X-Dashboard-Cache"]
    second = Afl.create!(farmer_name: "New farmer", fco_id: "995", fco: "Bhawanipatna", ics_id: "ICS-B", village_id: "V-B", tracenet_no: "CACHE-B")
    get dashboard_path, params: @filters
    assert_equal "miss", response.headers["X-Dashboard-Cache"]
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "2"
    second.update!(ics_id: "ICS-A")
    get dashboard_path, params: @filters
    assert_equal "miss", response.headers["X-Dashboard-Cache"]
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "1"
    second.destroy!
    get dashboard_path, params: @filters
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "1"
  end

  test "rendered responses are isolated by session office filters and entry mode" do
    Afl.create!(farmer_name: "Outside farmer", fco_id: "999", fco: "Other Office", ics_id: "ICS-OUTSIDE", tracenet_no: "CACHE-OUTSIDE")
    2.times { get dashboard_path, params: @filters }
    assert_equal "hit", response.headers["X-Dashboard-Cache"]
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "2"
    staff_session = open_session
    staff_session.post login_path, params: { login: @staff.user_name, password: "secret" }
    staff_session.get dashboard_path, params: @filters
    assert_not_equal "hit", staff_session.response.headers["X-Dashboard-Cache"]
    assert_not_includes staff_session.response.body, "Cache Owner"
    assert_includes staff_session.response.body, "Office Viewer"
    get dashboard_path, params: @filters.merge(fcoc: "Bhawanipatna")
    assert_not_equal "hit", response.headers["X-Dashboard-Cache"]
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "1"
    get dashboard_path, params: @filters.merge(entry_mode: "block_wise")
    assert_not_equal "hit", response.headers["X-Dashboard-Cache"]
    assert_select ".dashboard-view-switch-item.active span", text: "Block Wise"
  end
end
