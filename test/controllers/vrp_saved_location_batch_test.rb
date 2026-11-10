require "test_helper"

class VrpSavedLocationBatchTest < ActiveSupport::TestCase
  Selection = Struct.new(:gram_panchayat_ids, :village_ids)

  test "saved location batching preserves aliases inactive rows leading zeros duplicates and missing IDs" do
    rows = [
      ModuleRecord.create!(module_slug: "gram-panchayat-master", data: { "gram_panchayat_name" => "Primary GP", "village_name" => "Primary Village", "status" => "Inactive" }),
      ModuleRecord.create!(module_slug: "village-master", data: { "gram_panchayat" => "Alias GP", "village" => "Alias Village", "deleted" => true }),
      ModuleRecord.create!(module_slug: "lg-directory-list", data: { "gp_name" => "Legacy GP", "name" => "Legacy Village" }),
      ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "No requested name" })
    ]
    ids = [nil, "", " ", "Plain Label", rows[2].id.to_s, "00#{rows[0].id}", rows[1].id,
      rows[0].id.to_s, rows[3].id.to_s, "9223372036854775808", "000000000", "Plain Label"]
    controller = VrpsController.new
    selection = Selection.new(ids, ids)
    [[:vrp_saved_gp_names, %w[gram_panchayat_name gram_panchayat gp_name]],
     [:vrp_saved_village_names, %w[village_name village name]]].each do |method, keys|
      expected = ids.compact_blank.map do |id|
        next id.to_s unless id.to_s.match?(/\A\d+\z/)
        row = ModuleRecord.find_by(id: id)
        row ? keys.filter_map { |key| row.data[key].presence }.first || id.to_s : id.to_s
      end.compact_blank.uniq
      queries = []
      callback = ->(*args) do
        sql = args.last[:sql]
        queries << sql if sql.start_with?("SELECT") && sql.include?('"module_records"')
      end
      actual = nil
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { actual = controller.send(method, selection) }
      assert_equal expected, actual
      assert_equal 1, queries.size
    end
  end

  test "saved names observe later edits and avoid queries for text-only and empty selections" do
    row = ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Before" })
    controller = VrpsController.new
    selection = Selection.new([], [row.id.to_s])
    assert_equal ["Before"], controller.send(:vrp_saved_village_names, selection)
    row.update_columns(data: { "village_name" => "After" })
    assert_equal ["After"], controller.send(:vrp_saved_village_names, selection)
    queries = []
    callback = ->(*args) { queries << args.last[:sql] if args.last[:sql].start_with?("SELECT") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal [], controller.send(:vrp_saved_gp_names, nil)
      assert_equal [], controller.send(:vrp_saved_village_names, Selection.new([], []))
      assert_equal ["Text"], controller.send(:vrp_saved_gp_names, Selection.new(["Text", "Text"], []))
    end
    assert_empty queries
  end
end
