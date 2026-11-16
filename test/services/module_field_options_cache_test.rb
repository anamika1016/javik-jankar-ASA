require "test_helper"

class ModuleFieldOptionsCacheTest < ActiveSupport::TestCase
  setup do
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end
  teardown { Rails.cache = @cache }

  test "version probes are module scoped and unrelated training edits do not evict dropdowns" do
    source = ModuleRecord.create!(module_slug: "options-audit", data: { "label" => "Before", "status" => "Active" })
    unrelated = ModuleRecord.create!(module_slug: "unrelated-audit", data: { "photo" => "x" * 10000 })
    scope = ModuleRecord.where(module_slug: "options-audit").where("data::jsonb ->> 'status' = 'Active'")
    calls = 0
    reader = -> { ModuleFieldOptionsCache.fetch(scope, ["label"]) { calls += 1; scope.pluck(:data).map { |data| data["label"] } } }
    assert_equal ["Before"], reader.call
    unrelated.update_columns(data: { "photo" => "Changed" })
    assert_equal ["Before"], reader.call
    assert_equal 1, calls
    source.update_columns(data: { "label" => "After", "status" => "Active" })
    assert_equal ["After"], reader.call
    source.update_columns(data: { "label" => "After", "status" => "Inactive" })
    assert_empty reader.call
    source.update_columns(data: { "label" => "Restored", "status" => "Active" })
    assert_equal ["Restored"], reader.call
    source.destroy!
    assert_empty reader.call
    assert_equal 5, calls
    version_sql = ModuleFieldOptionsCache.revision_scope(scope).to_sql
    assert_includes version_sql, '"module_records"."module_slug"'
    refute_includes version_sql, "data::jsonb"
  end

  test "negative module scopes keep the complete revision fallback" do
    scope = ModuleRecord.where.not(module_slug: "excluded")
    assert_equal ModuleRecord.all.to_sql, ModuleFieldOptionsCache.revision_scope(scope).to_sql
  end

  test "direct imports moving a row between source modules invalidate both catalogues" do
    record = ModuleRecord.create!(module_slug: "import-source-a", data: { "label" => "Moved value" })
    read = lambda do |slug|
      scope = ModuleRecord.where(module_slug: slug)
      ModuleFieldOptionsCache.fetch(scope, ["label"]) { scope.pluck(:data).map { |data| data["label"] } }
    end
    assert_equal ["Moved value"], read.call("import-source-a")
    assert_empty read.call("import-source-b")
    original_updated_at = record.updated_at
    record.update_columns(module_slug: "import-source-b")
    assert_equal original_updated_at, record.reload.updated_at
    assert_empty read.call("import-source-a")
    assert_equal ["Moved value"], read.call("import-source-b")
    record.delete
    assert_empty read.call("import-source-b")
    ModuleRecord.create!(module_slug: "import-source-b", data: { "label" => "New import" })
    assert_equal ["New import"], read.call("import-source-b")
  end

  test "warm fields from one source use a single version probe per controller" do
    ModuleRecord.create!(module_slug: "options-probe-audit", data: { "first" => "One", "second" => "Two" })
    scope = ModuleRecord.where(module_slug: "options-probe-audit")
    warm = ModulesController.new
    %w[first second].each { |field| warm.send(:projected_module_field_values, scope, [field]) }
    controller = ModulesController.new
    probes = []
    callback = ->(*args) { sql = args.last[:sql]; probes << sql if sql.include?("STRING_AGG") }
    actual = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      actual = %w[first second].map { |field| controller.send(:projected_module_field_values, scope, [field]) }
    end
    assert_equal [["One"], ["Two"]], actual
    assert_equal 1, probes.size
    assert_match(/WHERE.*module_slug.*=/, probes.first)
  end
end
