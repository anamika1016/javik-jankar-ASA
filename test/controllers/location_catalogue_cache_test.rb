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
end
