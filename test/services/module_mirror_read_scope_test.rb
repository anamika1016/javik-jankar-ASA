require "test_helper"

class ModuleMirrorReadScopeTest < ActiveSupport::TestCase
  def with_ready(value)
    original = ModuleMirror.method(:ready?)
    ModuleMirror.define_singleton_method(:ready?) { value }
    yield
  ensure
    ModuleMirror.define_singleton_method(:ready?, original)
  end

  setup do
    @record = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process",
      data: { "status" => "Final Approved", "bill_month" => "June", "select_vrp" => "123" })
    ModuleBill.upsert({ id: @record.id, data: @record.data,
      created_at: @record.created_at, updated_at: @record.updated_at })
  end

  test "dedicated reads keep ids JSON and workflow status without reading the source table" do
    with_ready(true) do
      scope = ModuleMirror.read_scope(@record.module_slug)
      assert_equal @record.module_slug, scope.where_values_hash["module_slug"]
      refute_match(/FROM "module_records"/, scope.to_sql)
      assert_match(/FROM "module_bills"/, scope.to_sql)
      row = scope.find(@record.id)
      assert_equal @record.id, row.id
      assert_equal @record.data, row.data
      assert_equal @record.module_slug, row.module_slug
      assert row.readonly?
    end
  end

  test "existing projections and id filters work against the dedicated table" do
    with_ready(true) do
      scope = ModuleMirror.read_scope(@record.module_slug).where(id: @record.id)
      assert_equal [[@record.id, { "bill_month" => "June" }]],
        ModuleRecordReadQuery.projected_data_rows(scope, ["bill_month"])
      assert_equal [@record.data], ModuleRecordReadQuery.hydrate(scope.to_a).map(&:data)
    end
  end

  test "mixed queries retain legacy rows together with dedicated rows" do
    legacy = ModuleRecord.create!(module_slug: "unmigrated-read-test", data: { "label" => "Legacy" })
    with_ready(true) do
      rows = ModuleMirror.read_scope([@record.module_slug, legacy.module_slug])
        .where(id: [@record.id, legacy.id]).index_by(&:id)
      assert_equal @record.data, rows.fetch(@record.id).data
      assert_equal legacy.data, rows.fetch(legacy.id).data
    end
  end

  test "missing sync readiness keeps the original safe read" do
    with_ready(false) do
      assert_equal @record.data, ModuleMirror.read_scope(@record.module_slug).find(@record.id).data
    end
  end

  test "native dedicated JSONB reads avoid converting the payload to text in SQL" do
    with_ready(true) do
      scope = ModuleMirror.read_scope(@record.module_slug)
      refute_includes scope.to_sql, "data::text"
      assert_equal [@record.data], scope.where(id: @record.id).pluck(:data)
    end
  end

  test "mixed reads preserve legacy scalar strings arrays and numeric JSON values" do
    ["scalar", ["array", 1], 2, false].each do |value|
      # false is normally rejected by the presence validation, but old bulk
      # imports can contain it and the read path must keep the stored value.
      legacy = ModuleRecord.new(module_slug: "unmigrated-scalar-test", data: value)
      legacy.save!(validate: false)
      with_ready(true) do
        actual = ModuleMirror.read_scope([@record.module_slug, legacy.module_slug]).find(legacy.id)
        assert_equal value, actual.data
      end
    end
  end

  test "generic projections return the same fields for migrated and legacy rows" do
    legacy = ModuleRecord.create!(module_slug: "unmigrated-projection-test", data: { "bill_month" => ["July", 1] })
    ids = [@record.id, legacy.id]
    expected = ModuleRecordReadQuery.field_value_rows(ModuleRecord.where(id: ids).order(:id), ["bill_month", "missing"])
    with_ready(true) do
      scope = ModuleMirror.projection_scope.where(id: ids).order(:id)
      assert_equal expected, ModuleRecordReadQuery.field_value_rows(scope, ["bill_month", "missing"])
    end
  end

  test "generic active projections retain the original status and deletion rules" do
    ids = [@record.id]
    [{ "status" => " Active " }, { "status" => "Paid" }, { "deleted" => "yes" }, {}].each do |flags|
      record = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "bill_month" => "July" }.merge(flags))
      ModuleBill.upsert({ id: record.id, data: record.data, created_at: record.created_at, updated_at: record.updated_at })
      ids << record.id
    end
    legacy = ModuleRecord.create!(module_slug: "unmigrated-active-projection", data: { "status" => "Inactive" })
    ids << legacy.id
    expected = ModulesController.new.send(:active_module_records_scope_for_all_modules).where(id: ids).order(:id).pluck(:id)
    with_ready(true) do
      assert_equal expected, ModuleMirror.projection_scope(active_only: true).where(id: ids).order(:id).pluck(:id)
    end
  end

  test "source writes and in-place dirty tracking keep the original JSON text format" do
    data = { "nested" => { "values" => [1, false, nil, "हिंदी"] } }
    record = ModuleRecord.create!(module_slug: "text-format-test", data: data)
    connection = ModuleRecord.connection
    raw = connection.select_value("SELECT data FROM module_records WHERE id = #{record.id}")
    assert_equal JSON.dump(data), raw
    record.reload.data["nested"]["values"] << "Added"
    assert_predicate record, :changed?
    record.save!
    assert_equal data["nested"]["values"] + ["Added"], record.reload.data["nested"]["values"]
  end
end
