require "test_helper"

class CatalogueUnusedReadsTest < ActiveSupport::TestCase
  test "directory and office screens skip unused saved records but retain edit reads" do
    controller = ModulesController.new
    %w[lg-directory-list office-list].each do |slug|
      controller.instance_variable_set(:@slug, slug)
      controller.instance_variable_set(:@record, nil)
      assert_not controller.send(:module_records_required_for_show?)
      controller.instance_variable_set(:@record, ModuleRecord.new(module_slug: slug))
      assert controller.send(:module_records_required_for_show?)
    end
  end

  test "directory bulk matching retains duplicates across sources and excludes unrelated rows" do
    common = { "state" => "State", "district" => "District", "village" => "Village" }
    first = ModuleRecord.create!(module_slug: "lg-directory-list", data: common)
    duplicate = ModuleRecord.create!(module_slug: "village-master", data: common)
    ModuleRecord.create!(module_slug: "village-master", data: common.merge("village" => "Other"))
    ModuleRecord.create!(module_slug: "other-target", data: common)
    controller = ModulesController.new
    expected = ModuleRecord.where(module_slug: controller.send(:lg_directory_allowed_slugs)).to_a.select do |row|
      controller.send(:lg_directory_row_key, controller.send(:lg_directory_row_from_record, row,
        controller.send(:lg_directory_aliases_for_slug, row.module_slug))) ==
        controller.send(:lg_directory_row_key, controller.send(:lg_directory_row_from_record, first,
          controller.send(:lg_directory_aliases_for_slug, first.module_slug)))
    end
    assert_equal expected.map(&:id), controller.send(:lg_directory_matching_records, [first, duplicate, first]).map(&:id)
    assert_equal [first.id, duplicate.id].sort, expected.map(&:id).sort
    assert_empty controller.send(:lg_directory_matching_records, [])
  end

  test "admin target reads retain all records without building unused JJ visibility indexes" do
    record = ModuleRecord.create!(module_slug: "other-target", data: { "created_by_id" => "missing" })
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, "other-target-list")
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new
    controller.define_singleton_method(:admin_dashboard_user?) { true }
    controller.define_singleton_method(:preload_target_visibility_vrps!) { |*| raise "Unused admin JJ preload" }
    controller.define_singleton_method(:preload_other_target_contact_numbers!) { |*| }
    assert_equal [record.id], controller.send(:module_records).map(&:id)
  end
end
