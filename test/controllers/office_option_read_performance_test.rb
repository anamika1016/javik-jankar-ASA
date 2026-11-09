require "test_helper"

class OfficeOptionReadPerformanceTest < ActiveSupport::TestCase
  test "office mappings reuse reads while preserving output and independent mutable results" do
    ModuleRecord.create!(module_slug: "office-category-add", data: {
      "office_name" => "FCO", "stakeholder" => "ASA", "status" => "Active" })
    parent = ModuleRecord.create!(module_slug: "parent-office-add", data: {
      "parent_office_name" => "Parent", "stakeholder" => "ASA", "status" => "Active" })
    controller = ModulesController.new
    [[:office_category_mappings, :build_office_category_mappings],
      [:parent_office_mappings, :build_parent_office_mappings]].each do |reader, builder|
      expected = controller.send(builder)
      allocations = 0
      first = controller.send(reader)
      ActiveSupport::Notifications.subscribed(->(*args) { allocations += args.last[:record_count] }, "instantiation.active_record") do
        assert_equal expected, controller.send(reader)
      end
      assert_equal 0, allocations
      refute_empty first
      first.first[:stakeholder].replace("Changed caller")
      assert_equal expected, controller.send(reader)
    end
    parent.update!(data: parent.data.merge("parent_office_name" => "Updated Parent"))
    assert_equal "Updated Parent", ModulesController.new.send(:parent_office_mappings).first[:parent_office_name]
  end
end
