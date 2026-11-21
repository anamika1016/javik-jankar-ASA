require "test_helper"

class VrpDetailVillageIndexTest < ActiveSupport::TestCase
  test "indexed detail selection preserves legacy labels types duplicate matches and exact source order" do
    entries = [
      { "village_name" => " Name ", "name" => "Alias", "state_name" => "State" },
      { "village_name" => "NAME", "state_name" => "Other State" },
      { "village_name" => false, "village" => "Fallback" },
      { "village_name" => "किसान", "name" => "ÉCOLE" },
      { "village_name" => ["Legacy", "Array"], "name" => 17 },
      { "village_name" => { "zz" => "Z", "aa" => "A" }, "name" => { "hi" => "नाम", "en" => "Name" } },
      { "village_name" => "Inactive", "status" => "Inactive" },
      { "village_name" => "Hidden flag", "deleted" => "\tYES\n" }
    ]
    rows = entries.each_with_index.map { |data, i| ModuleRecord.create!(module_slug: "village-master", data: data.merge("unused_import" => "x" * 1000), created_at: i.days.ago) }
    ModuleRecord.create!(module_slug: "state-master", data: { "village_name" => "Name" })
    selections = [[rows.first.id.to_s], ["00#{rows.first.id}"], [" name ", "Alias"], ["Fallback"], ["किसान", "école"], [17, ["Legacy", "Array"].to_s], [{ "zz" => "Z", "aa" => "A" }.to_s, { "hi" => "नाम", "en" => "Name" }.to_s], ["missing"], ["Hidden flag", rows.last.id.to_s]]
    selections.each do |values|
      legacy = VrpsController.new
      expected = legacy.send(:active_records_for_location, "village-master").select do |row|
        legacy.send(:vrp_detail_location_record_matches?, row, values, "village-master", "village_name")
      end
      actual = VrpsController.new.send(:vrp_detail_village_records, values)
      assert_equal expected.map(&:attributes), actual.map(&:attributes), values.inspect
    end
    rows.first.update_columns(data: rows.first.data.merge("village_name" => "Changed", "name" => "Changed alias"))
    assert_empty VrpsController.new.send(:vrp_detail_village_records, ["Alias"])
    assert_equal [rows.first.id], VrpsController.new.send(:vrp_detail_village_records, ["Changed alias"]).map(&:id)
  end

  test "warm selection instantiates only selected records and keeps their complete data" do
    selected = ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Selected", "unused_import" => "Kept on selected detail" })
    80.times { |i| ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Other #{i}", "unused_import" => "x" * 5000 }) }
    VrpsController.new.send(:vrp_detail_village_index)
    instantiated = 0
    observer = ->(*args) { instantiated += args.last[:record_count] }
    rows = nil
    ActiveSupport::Notifications.subscribed(observer, "instantiation.active_record") do
      rows = VrpsController.new.send(:vrp_detail_village_records, [selected.id.to_s])
    end
    assert_equal 1, instantiated
    assert_equal [selected.id], rows.map(&:id)
    assert_equal selected.data, rows.first.data
  end

  test "immutable detail index follows direct edits and deletes without sharing mutable detail data" do
    row = ModuleRecord.create!(module_slug: "village-master", data: {
      "village_name" => "Original village", "name" => "Original alias", "notes" => ["Complete detail"]
    })
    cache = ImmutableCatalogueStore.new(size: 1.megabyte)
    controller = lambda do
      VrpsController.new.tap do |instance|
        instance.define_singleton_method(:vrp_location_catalogue_cache) { cache }
        instance.define_singleton_method(:shared_form_catalogue_cache) { nil }
      end
    end
    index = controller.call.send(:vrp_detail_village_index)
    assert_predicate index, :frozen?
    assert_predicate index.fetch("original alias").first, :frozen?
    detail = controller.call.send(:vrp_detail_village_records, ["Original alias"]).first
    detail.data["notes"] << "Request-only change"
    assert_equal ["Complete detail"], controller.call.send(:vrp_detail_village_records, [row.id]).first.data["notes"]

    row.update_columns(data: row.data.merge("village_name" => "Updated village", "name" => "Updated alias"))
    assert_empty controller.call.send(:vrp_detail_village_records, ["Original alias"])
    assert_equal [row.id], controller.call.send(:vrp_detail_village_records, ["Updated alias"]).map(&:id)
    ModuleRecord.where(id: row.id).delete_all
    assert_empty controller.call.send(:vrp_detail_village_records, ["Updated alias", row.id])
    refute controller.call.send(:vrp_detail_village_index).key?("updated alias")
  end
end
