require "test_helper"

class ModuleMasterPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "master_pagination_admin", password: "secret",
      first_name: "Admin", user_type: "admin", status: "Active")
    @records = 16.times.map do |index|
      ModuleRecord.create!(module_slug: "village-master", data: {
        "village_name" => format("PAGINATION_VILLAGE_%02d", index), "status" => "Active"
      })
    end
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  test "master records render one server page while preserving search and actions" do
    get module_path("village-master", q: "PAGINATION_VILLAGE")
    assert_response :success
    assert_includes saved_record_table_text, "PAGINATION_VILLAGE_00"
    assert_not_includes saved_record_table_text, "PAGINATION_VILLAGE_15"
    assert_includes response.body, "Page 1 of 2"
    assert_includes response.body, "data-turbo-method=\"patch\""
    assert_includes response.body, "data-turbo-method=\"delete\""

    get module_path("village-master", page: 2, q: "PAGINATION_VILLAGE")
    assert_response :success
    assert_includes saved_record_table_text, "PAGINATION_VILLAGE_15"
    assert_not_includes saved_record_table_text, "PAGINATION_VILLAGE_00"

    get module_path("village-master", q: "PAGINATION_VILLAGE_07")
    assert_response :success
    assert_includes saved_record_table_text, "PAGINATION_VILLAGE_07"
    assert_not_includes saved_record_table_text, "PAGINATION_VILLAGE_08"
  end

  private

  def saved_record_table_text
    Nokogiri::HTML(response.body).at_css("#module_saved_records").text
  end
end
