require "test_helper"

class LocationCatalogueCacheTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ModulesController::LG_DIRECTORY_MEMORY_CACHE.clear
  end

  teardown { Rails.cache = @original_cache }

  def catalogue
    ModulesController.new.send(:location_hierarchy_mappings)
  end

  def location_master_controller(slug)
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, slug)
    controller.define_singleton_method(:request) { Struct.new(:format).new(Mime[:html]) }
    controller
  end

  test "separate requests reuse the catalogue without rereading location payloads" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Cache State" })
    expected = catalogue
    queries = []
    callback = ->(*args) { queries << args.last[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      actual = catalogue
      assert_equal expected, actual
      actual.find { |row| row[:id] == record.id.to_s }[:state] = "Changed in memory"
    end
    assert queries.any? { |sql| sql.include?("SUM((xmin::text)::bigint)") }
    assert_empty queries.grep(/jsonb_object_agg/)
    assert_equal expected, catalogue
  end

  test "creates edits soft deletes and hard deletes invalidate across requests" do
    catalogue
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "New State" })
    assert catalogue.any? { |row| row[:id] == record.id.to_s && row[:state] == "New State" }
    record.update!(data: { "state_name" => "Renamed State" })
    assert catalogue.any? { |row| row[:id] == record.id.to_s && row[:state] == "Renamed State" }
    record.update!(data: record.data.merge("deleted" => true))
    assert catalogue.none? { |row| row[:id] == record.id.to_s }
    record.update!(data: { "state_name" => "Restored State" })
    assert catalogue.any? { |row| row[:id] == record.id.to_s }
    # Delete an older row: the maximum timestamp alone would not detect it.
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Newest State" })
    catalogue
    record.destroy!
    assert catalogue.none? { |row| row[:id] == record.id.to_s }
  end

  test "editing an older row invalidates even when another row has a future timestamp" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Before edit" })
    ModuleRecord.create!(module_slug: "state-master", updated_at: 1.day.from_now,
      data: { "state_name" => "Imported future row" })
    catalogue
    record.update!(data: { "state_name" => "After edit" })
    assert_equal "After edit", catalogue.find { |row| row[:id] == record.id.to_s }[:state]
  end

  test "data updates with an unchanged timestamp cannot leave stale dropdowns" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Before update" })
    catalogue
    record.update_columns(data: { "state_name" => "After update" })
    assert_equal "After update", catalogue.find { |row| row[:id] == record.id.to_s }[:state]
  end

  test "LG directory reuses its derived rows and invalidates after a location edit" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Cached LG State" })
    first = ModulesController.new.send(:lg_directory_rows)
    assert_includes first.map { |row| row[:state] }, "Cached LG State"

    payload_reads = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      payload_reads << sql if sql.include?(%Q{"module_records"."data"})
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      second = ModulesController.new.send(:lg_directory_rows)
      assert_equal first, second
    end
    assert_empty payload_reads

    record.update_columns(data: { "state_name" => "Updated LG State" })
    updated = ModulesController.new.send(:lg_directory_rows)
    assert_includes updated.map { |row| row[:state] }, "Updated LG State"
    assert_not_includes updated.map { |row| row[:state] }, "Cached LG State"
  end

  test "location master saved records reuse payloads and invalidate after a direct edit" do
    record = ModuleRecord.create!(module_slug: "village-master", data: {
      "state_name" => "Cache State", "village_name" => "Before Village"
    })
    first = location_master_controller("village-master").send(:module_records)
    assert_equal "Before Village", first.find { |row| row.id == record.id }.data["village_name"]

    payload_reads = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      payload_reads << sql if sql.include?(%Q{"module_records"."data"})
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      second = location_master_controller("village-master").send(:module_records)
      assert_equal first.map(&:id), second.map(&:id)
    end
    assert_empty payload_reads

    record.update_columns(data: record.data.merge("village_name" => "After Village"))
    updated = location_master_controller("village-master").send(:module_records)
    assert_equal "After Village", updated.find { |row| row.id == record.id }.data["village_name"]
  end

  test "form location projections are shared across requests and still invalidate" do
    record = ModuleRecord.create!(module_slug: "village-master", data: {
      "state_name" => "Projection State", "village_name" => "Before Projection"
    })

    first_controller = ModulesController.new
    first_controller.send(:preload_location_records!, ["village-master"])
    first = first_controller.send(:active_records_for_location, "village-master")
    assert_equal "Before Projection", first.find { |row| row.id == record.id }.data["village_name"]

    projection_reads = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      projection_reads << sql if sql.include?("jsonb_object_agg")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      second_controller = ModulesController.new
      second_controller.send(:preload_location_records!, ["village-master"])
      second = second_controller.send(:active_records_for_location, "village-master")
      assert_equal first.map(&:id), second.map(&:id)
      second.find { |row| row.id == record.id }.data["village_name"] = "Request-local edit"
    end
    assert_empty projection_reads

    fresh_controller = ModulesController.new
    fresh_controller.send(:preload_location_records!, ["village-master"])
    fresh = fresh_controller.send(:active_records_for_location, "village-master")
    assert_equal "Before Projection", fresh.find { |row| row.id == record.id }.data["village_name"]

    record.update_columns(data: record.data.merge("village_name" => "After Projection"))
    updated_controller = ModulesController.new
    updated_controller.send(:preload_location_records!, ["village-master"])
    updated = updated_controller.send(:active_records_for_location, "village-master")
    assert_equal "After Projection", updated.find { |row| row.id == record.id }.data["village_name"]
  end
end
