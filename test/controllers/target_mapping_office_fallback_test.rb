require "test_helper"

class TargetMappingOfficeFallbackTest < ActiveSupport::TestCase
  test "unavailable office services return empty options instead of URL strings" do
    controller = TargetMappingsController.new
    original = OfficeTerritoryDirectory.method(:items)
    OfficeTerritoryDirectory.define_singleton_method(:items) { [] }
    assert_equal [], controller.send(:office_list_items)
    assert_equal [], controller.send(:office_list_fco_options)
  ensure
    OfficeTerritoryDirectory.define_singleton_method(:items, original) if original
  end

  test "each target mapping request uses the shared office snapshot" do
    calls = 0
    offices = [{ "id" => 18, "name" => "Ranapur - FCO" }]
    original = OfficeTerritoryDirectory.method(:items)
    OfficeTerritoryDirectory.define_singleton_method(:items) { calls += 1; offices }
    controller = TargetMappingsController.new
    assert_equal offices, controller.send(:office_list_items)
    assert_equal offices, controller.send(:office_list_items)
    assert_equal 1, calls
  ensure
    OfficeTerritoryDirectory.define_singleton_method(:items, original) if original
  end

  test "block options contain only the selected FCO territory without repeated block IDs" do
    controller = TargetMappingsController.new
    blocks = %w[Jhabua Meghnagar Petlawad Rama Ranapur Thandla].each_with_index.map do |name, index|
      { "id" => 83 + index, "name" => { "en" => name } }
    end
    offices = [
      { "id" => 18, "name" => "Ranapur - FCO", "territory_zones" => [
        { "block" => blocks },
        { "block" => [{ "id" => 83, "name" => { "en" => "JHABUA" } }] }
      ] },
      { "id" => 54, "name" => "Ranapur - TO", "parent" => { "id" => 18, "name" => "Ranapur - FCO" },
        "territory_zones" => [{ "block" => [{ "id" => 89, "name" => { "en" => "Bajna" } }] }] },
      { "id" => 99, "name" => "Ranapur - FCO",
        "territory_zones" => [{ "block" => [{ "id" => 112, "name" => { "en" => "Neemuch" } }] }] }
    ]
    controller.define_singleton_method(:office_list_items) { offices }

    expected = blocks.map { |block| "#{block['id']}||#{block.dig('name', 'en')}" }
    assert_equal expected, controller.send(:office_block_options, "18||Ranapur - FCO").map { |option| option[:value] }
    assert_equal expected, controller.send(:office_block_options, "18").map { |option| option[:value] }
    assert_empty controller.send(:office_block_options, "")
    assert_empty controller.send(:office_block_options, "999||Ranapur - FCO")
  end

test "uses direct FPC blocks when an FCO has no blocks of its own" do
  controller = TargetMappingsController.new
  offices = [
    { "id" => 15, "name" => "Bhawanipatna - FCO", "territory_zones" => [] },
    { "id" => 156, "name" => "Budhadangar FPC", "parent" => { "id" => 15, "name" => "Bhawanipatna - FCO" },
      "territory_zones" => [{ "block" => [
        { "id" => 42, "name" => { "en" => "Bhawanipatna" } },
        { "id" => 43, "name" => { "en" => "Kesinga" } }
      ] }] },
    { "id" => 94, "name" => "Bhawanipatna - TO", "parent" => { "id" => 15, "name" => "Bhawanipatna - FCO" },
      "territory_zones" => [{ "block" => [{ "id" => 99, "name" => { "en" => "Unrelated" } }] }] }
  ]
  controller.define_singleton_method(:office_list_items) { offices }

  assert_equal ["42||Bhawanipatna", "43||Kesinga"], controller.send(:office_block_options, "15||Bhawanipatna - FCO").map { |option| option[:value] }
end

end
