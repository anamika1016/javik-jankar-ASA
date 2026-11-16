require "test_helper"
require "tmpdir"

class SharedFormCatalogueTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("shared-form-test-")
    @shared = SharedCatalogueCache.new(@directory)
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @record = ModuleRecord.create!(module_slug: "village-master", data: {
      "state_name" => "Shared State", "village_name" => "Shared Village <&", "status" => "Active"
    })
  end
  teardown do
    Rails.cache = @previous_cache
    ModulesController::LG_DIRECTORY_MEMORY_CACHE.clear
    FileUtils.remove_entry(@directory)
  end

  test "directory and sorted master records reuse shared data without changing rows or order" do
    ModulesController::LG_DIRECTORY_MEMORY_CACHE.clear
    expected = consumer(ModulesController).send(:lg_directory_rows)
    ModulesController::LG_DIRECTORY_MEMORY_CACHE.clear
    Rails.cache.clear
    next_worker = consumer(ModulesController)
    next_worker.define_singleton_method(:build_lg_directory_rows) { raise "Rebuilt shared directory" }
    assert_equal expected, next_worker.send(:lg_directory_rows)
    first = consumer(ModulesController)
    first.instance_variable_set(:@module, ModulesController::MODULES.fetch("village-master"))
    attributes = first.send(:cached_location_master_page_attributes, "village-master")
    Rails.cache.clear
    second = consumer(ModulesController)
    second.instance_variable_set(:@module, ModulesController::MODULES.fetch("village-master"))
    second.define_singleton_method(:cached_location_master_records) { |_| raise "Rebuilt master sort" }
    assert_equal attributes, second.send(:cached_location_master_page_attributes, "village-master")
    @record.update!(data: @record.data.merge("village_name" => "Edited Shared Master"))
    changed = consumer(ModulesController)
    changed.instance_variable_set(:@module, ModulesController::MODULES.fetch("village-master"))
    result = changed.send(:cached_location_master_page_attributes, "village-master")
    assert result.any? { |row| JSON.parse(row["data"])["village_name"] == "Edited Shared Master" }
    assert_includes consumer(ModulesController).send(:lg_directory_rows).map { |row| row[:village] }, "Edited Shared Master"
  end

  test "all form consumers reuse byte equivalent shared fills after worker RAM is cleared and invalidate edits" do
    [
      [ModulesController, :location_hierarchy_browser_attribute, :location_hierarchy_browser_json],
      [VrpsController, :vrp_location_browser_attribute, :location_hierarchy_mappings],
      [UsersController, :user_form_options_payload, :build_user_form_options_payload]
    ].each do |type, reader, builder|
      Rails.cache.clear
      first = consumer(type)
      expected = first.send(reader)
      Rails.cache.clear # Simulate a new worker with no process-local entries.
      second = consumer(type)
      second.define_singleton_method(builder) { raise "Shared value rebuilt in another worker" }
      actual = second.send(reader)
      assert_equal expected, actual, type.name
      assert_predicate actual, :html_safe? unless actual.is_a?(Hash)
      @record.update!(data: @record.data.merge("village_name" => "Edited #{type.name}"))
      changed = consumer(type).send(reader)
      refute_equal expected, changed
      assert_includes changed.to_s, "Edited #{type.name}"
    end
  end

  private

  def consumer(type)
    shared = @shared
    type.new.tap { |controller| controller.define_singleton_method(:shared_form_catalogue_cache) { shared } }
  end
end
