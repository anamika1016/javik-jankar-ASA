require "test_helper"

class SelectedModuleRecordLabelsTest < ActiveSupport::TestCase
  test "projected lookup rows retain requested JSON values and exclude large unrelated data" do
    data = { "gp_code" => "991", "gram_name" => "Gram <&", "status" => " Active ",
      "deleted" => false, "nested" => ["A", { "B" => 3 }], "nullable" => nil, "odd'key" => 17,
      "unused_upload" => "x" * 100_000 }
    record = ModuleRecord.create!(module_slug: "gram-panchayat-master", data: data)
    fields = data.keys - ["unused_upload"]
    rows = ModuleRecordReadQuery.projected_data_rows(ModuleRecord.where(id: record.id), fields)
    assert_equal [[record.id, data.except("unused_upload")]], rows
    assert_empty ModuleRecordReadQuery.projected_data_rows(ModuleRecord.all, [])
  end

  test "selected labels are batched while preserving order duplicates missing values and slug boundaries" do
    records = 20.times.map { |i| ModuleRecord.create!(module_slug: "project-master", data: { "project_name" => "Project #{i}", "unused_upload" => "x" * 1000 }) }
    other = ModuleRecord.create!(module_slug: "state-master", data: { "project_name" => "Wrong source" })
    ids = [records.last.id, records.first.id.to_s, records.last.id, other.id, "Missing legacy label", nil]
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] if args.last[:sql].match?(/SELECT.*FROM "module_records"/m) }
    controller = VrpsController.new
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      assert_equal "Project 19, Project 0, Project 19, Missing legacy label", controller.send(:module_record_labels, "project-master", ids, "project_name")
      assert_equal "Project 0", controller.send(:module_record_label, "project-master", records.first.id, "project_name")
      assert_equal "Project 0", controller.send(:module_record_label, "project-master", "00#{records.first.id}", "project_name")
      assert_equal "Project 19", controller.send(:vrp_detail_location_label, "project-master", other.id, [records.last.id], "project_name")
    end
    assert_equal 1, queries.size
    assert_includes queries.first, '"module_records"."id" IN'
  end

  test "projected field values keep aliases types arrays duplicates and original record ordering" do
    older = ModuleRecord.create!(module_slug: "ics-master", data: { "ics_name" => ["A", "B"], "name" => 17, "unused_upload" => "x" * 100_000 }, created_at: 1.day.ago)
    newer = ModuleRecord.create!(module_slug: "ics-master", data: { "ics_name" => " A, C ", "name" => false, "select_ics" => "C" })
    ModuleRecord.create!(module_slug: "ics-master", data: { "ics_name" => "Inactive", "status" => "Inactive" })
    controller = ModulesController.new
    keys = %w[ics_name name ics select_ics]
    scope = controller.send(:active_module_records_scope, "ics-master").order(created_at: :desc)
    expected = scope.flat_map { |record| keys.filter_map { |key| record.data[key].presence } }
      .flat_map { |value| value.is_a?(Array) ? value : value.to_s.split(",") }.map(&:to_s).map(&:strip).reject(&:blank?)
    assert_equal ["A", "C", "C", "A", "B", "17"], expected
    instantiated = 0
    subscriber = ->(*args) { instantiated += args.last[:record_count] }
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      assert_equal expected, controller.send(:module_record_values, "ics-master", *keys)
    end
    assert_equal 0, instantiated
    assert_equal [newer.id, older.id], scope.pluck(:id)
    assert_empty ModuleRecordReadQuery.field_value_rows(scope, [])
  end
end
