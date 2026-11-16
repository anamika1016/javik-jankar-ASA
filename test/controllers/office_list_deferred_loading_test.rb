require "test_helper"

class OfficeListDeferredLoadingTest < ActionController::TestCase
  tests ModulesController

  setup do
    @controller.define_singleton_method(:current_app_user) { { "id" => "1", "record_type" => "User", "user_type" => "admin" } }
    @calls = 0
    bump = -> { @calls += 1 }
    @controller.define_singleton_method(:office_list_api_items) do
      bump.call
      [{ "id" => "41", "name" => "Office <One>", "territory_zones" => [{ "state" => [{ "name" => { "en" => "State" } }] }] }]
    end
  end

  test "office navigation renders without waiting for remote list" do
    get :show, params: { slug: "office-list" }
    assert_response :success
    assert_equal 0, @calls
    assert_select 'turbo-frame#office_list_content[src=?]', module_path("office-list")
    assert_select 'noscript a[href*="load_offices=1"]', 1
  end

  test "loaded office frame preserves the full table and export target" do
    request.headers["Turbo-Frame"] = "office_list_content"
    get :show, params: { slug: "office-list" }
    assert_response :success
    assert_equal 1, @calls
    frame_doc = Nokogiri::HTML(response.body)
    expected_cells = frame_doc.css("#office_detail_list th, #office_detail_list td").map { |cell| cell.text.strip }
    assert_select 'turbo-frame#office_list_content[src]', 0
    assert_select 'a[data-turbo-frame="_top"][href*="export.xlsx"]', 1
    assert_select '#office_detail_list td', text: 'Office <One>'
    request.set_header("HTTP_TURBO_FRAME", nil)
    get :show, params: { slug: "office-list", load_offices: "1" }
    assert_response :success
    assert_equal expected_cells, Nokogiri::HTML(response.body).css("#office_detail_list th, #office_detail_list td").map { |cell| cell.text.strip }
  end
end
