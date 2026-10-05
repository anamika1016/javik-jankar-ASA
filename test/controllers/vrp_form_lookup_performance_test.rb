require "test_helper"

class VrpFormLookupPerformanceTest < ActiveSupport::TestCase
  test "cluster enrichment loads ordered users once and preserves inactive filtering" do
    User.create!(first_name: "Lookup", last_name: "Person", user_name: "lookup_person", email: "lookup_person@example.com", password: "secret", status: "Active")
    controller = VrpsController.new
    mapping = { value: "lookup_person", label: "Original" }
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "users"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      first = controller.send(:enrich_cluster_mapping_from_user, mapping)
      assert_equal "Lookup Person", first[:value]
      assert_equal first, controller.send(:enrich_cluster_mapping_from_user, mapping)
      assert_equal({ value: "missing", label: "Missing" }, controller.send(:enrich_cluster_mapping_from_user, { value: "missing", label: "Missing" }))
    end
    assert_equal 1, queries.size
  end

  test "module labels cache missing rows and preserve literal fallback" do
    controller = VrpsController.new
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "module_records"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      3.times { assert_equal "Unknown", controller.send(:module_record_label, "state-master", "Unknown", "state_name") }
    end
    assert_equal 1, queries.size
  end
end
