require "test_helper"

class LgDirectoryReadTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "directory_read_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
    @row = ModuleRecord.create!(module_slug: "lg-directory-list", data: {
      "state_name" => "Directory State", "district_name" => "Directory District",
      "village_name" => "Village <&", "status" => "Inactive"
    })
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ModulesController::LG_DIRECTORY_MEMORY_CACHE.clear
  end

  teardown { Rails.cache = @previous_cache }

  test "directory renders saved projected rows with original controls without loading unused records" do
    queries = []
    callback = ->(*args) do
      payload = args.last
      if Array(payload[:binds]).any? { |bind| (bind.respond_to?(:value_for_database) ? bind.value_for_database : bind) == "lg-directory-list" }
        queries << payload[:sql]
      end
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get module_path("lg-directory-list")
    end
    assert_response :success
    assert_select "#lg_directory_all_list tbody tr", count: 1
    assert_select "td", text: "Village <&"
    assert_select "span.status-pill.inactive", text: "Inactive"
    assert_select "input[name='row_tokens[]'][value='lg-directory-list:#{@row.id}']"
    assert_select "button[name='bulk_action']", count: 4
    assert_select "a.export", count: 1
    assert_empty queries.grep(/SELECT "module_records"\.\*.*FROM "module_records"/)
    get module_path("lg-directory-list", table: "Village Name", q: "absent")
    assert_response :success
    assert_select "input[name='row_tokens[]']", count: 0
    get module_path("lg-directory-list", table: "Village Name", q: "Village")
    assert_response :success
    assert_select "input[name='row_tokens[]']", count: 1
  end
end
