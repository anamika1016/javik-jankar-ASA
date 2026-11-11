require "test_helper"

class MasterEditPaginationTest < ActionDispatch::IntegrationTest
  setup do
    admin = User.create!(user_name: "master_edit_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    post login_path, params: { login: admin.user_name, password: "secret" }
    @rows = 32.times.map do |i|
      ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => format("Village %02d", i),
        "state_name" => "State", "status" => "Active" })
    end
    @editing = @rows.last
  end

  test "master edit renders one saved page while keeping the selected record and full navigation" do
    url = edit_module_record_path("village-master", @editing)
    get url
    assert_response :success
    assert_select "#module_saved_records tbody tr", count: 15
    assert_select "form[action='#{module_record_path('village-master', @editing)}'] input[name='module_record[village_name]'][value='Village 31']"
    assert_select "turbo-frame#module_saved_records_page[target='_top']", count: 1
    assert_select "#module_saved_records_page form.list-search[action='#{url}'][data-turbo-frame='module_saved_records_page']"
    assert_select "a.page-link[data-turbo-frame='module_saved_records_page'][href='#{url}?page=2']", text: "Next"
    assert_select "#module-form", count: 1
    assert_select "#module_saved_records_page #module-form", count: 0

    get url, params: { page: 3 }, headers: { "Turbo-Frame" => "module_saved_records_page" }
    assert_response :success
    assert_select "#module_saved_records tbody tr", count: 2
    assert_select "#module-form", count: 0
    assert_select "[data-location-map]", count: 0
    assert_select "#module_saved_records td", text: "Village 31"
    assert_select "#module_saved_records a.table-action[href='#{url}']", text: "Edit"

    get url, params: { q: "Village 07" }, headers: { "Turbo-Frame" => "module_saved_records_page" }
    assert_response :success
    assert_select "#module_saved_records tbody tr", count: 1
    assert_select "#module_saved_records td", text: "Village 07"
    assert_select "#module-form", count: 0
  end
end
