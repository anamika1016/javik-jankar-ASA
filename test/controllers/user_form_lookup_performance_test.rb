require "test_helper"

class UserFormLookupPerformanceTest < ActiveSupport::TestCase
  test "user form preload returns the same active options with one batch query" do
    base_time = Time.current
    ModuleRecord.create!(module_slug: "state-master", created_at: base_time, data: { "state_name" => "Active State", "status" => "Active" })
    ModuleRecord.create!(module_slug: "state-master", created_at: base_time + 1.second, data: { "state_name" => "Spaced State", "status" => " Active " })
    ModuleRecord.create!(module_slug: "state-master", created_at: base_time + 2.seconds, data: { "state_name" => "Inactive State", "status" => "Inactive" })
    ModuleRecord.create!(module_slug: "state-master", created_at: base_time + 3.seconds, data: { "state_name" => "Deleted State", "deleted" => " YES " })
    controller = UsersController.new
    queries = []
    callback = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.start_with?("SELECT") && sql.include?(%Q{FROM "module_records"})
    end

    options = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      controller.send(:preload_user_form_module_records!)
      options = controller.send(:module_record_options, "state-master", "state_name")
    end

    assert_equal ["Spaced State", "Active State"], options
    assert_equal 1, queries.size
    assert_includes queries.first, "discarded"
    assert_includes queries.first, "is_deleted"
  end
end
