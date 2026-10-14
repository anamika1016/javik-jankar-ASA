require "test_helper"

class VrpFormLookupPerformanceTest < ActiveSupport::TestCase
  test "form option readers share records without changing labels or active filtering" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Read State", "status" => "Active" })
    spaced_active = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Spaced Active", "status" => " Active " })
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Hidden State", "status" => "Inactive" })
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Deleted State", "deleted" => " YES " })
    controller = VrpsController.new
    queries = []
    callback = ->(*args) { queries << args.last[:sql] if args.last[:sql].match?(/SELECT.*FROM "module_records"/m) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal [["Read State", record.id], ["Spaced Active", spaced_active.id]], controller.send(:module_record_options, "state-master", "state_name")
      assert_equal ["Spaced Active", "Read State"], controller.send(:text_module_record_options, "state-master", "state_name")
      assert_equal [spaced_active.id, record.id], controller.send(:active_records_for_location, "state-master").map(&:id)
    end
    assert_equal 1, queries.size
  end

  test "plain hierarchy labels and registration enrichment share one user query" do
    User.create!(first_name: "Plain", last_name: "Coordinator", user_name: "plain_lookup_cc",
      email: "plain-lookup-cc@example.test", password: "secret", role: "Cluster Incharge", status: "Active")
    controller = VrpsController.new
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "users"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert controller.send(:user_record_cluster_incharge_label?, "Plain Coordinator")
      10.times { |index| assert_not controller.send(:user_record_cluster_incharge_label?, "Missing #{index}") }
      assert_equal "Plain Coordinator", controller.send(:enrich_cluster_mapping_from_user,
        { value: "plain_lookup_cc", label: "Saved" })[:value]
    end
    assert_equal 1, queries.size
  end

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
