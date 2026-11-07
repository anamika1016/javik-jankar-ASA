require "test_helper"

class FormLocationRenderCacheTest < ActiveSupport::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @record = ModuleRecord.create!(module_slug: "village-master", data: {
      "state_name" => "State", "village_name" => "Village <&\"' ", "status" => "Active"
    })
  end

  teardown { Rails.cache = @previous_cache }

  test "user attribute matches old HTML escaping and warm forms reuse serialization" do
    first = UsersController.new
    first.send(:load_form_options)
    expected = ERB::Util.html_escape(ERB::Util.json_escape(first.instance_variable_get(:@location_hierarchy_mappings).to_json))
    assert_equal expected, first.instance_variable_get(:@location_hierarchy_browser_attribute)
    assert_predicate first.instance_variable_get(:@location_hierarchy_browser_attribute), :html_safe?
    first.instance_variable_get(:@village_options).clear
    warm = UsersController.new
    warm.define_singleton_method(:build_user_form_options_payload) { raise "Warm forms must reuse cached payload" }
    warm.send(:load_form_options)
    assert_equal expected, warm.instance_variable_get(:@location_hierarchy_browser_attribute)
    assert_not_empty warm.instance_variable_get(:@village_options)
  end

  test "user form cache detects timestamp preserving edits and savepoint rollback" do
    before = UsersController.new.send(:user_form_options_payload)
    ModuleRecord.transaction(requires_new: true) do
      @record.update_columns(data: @record.data.merge("village_name" => "Changed Village"))
      changed = UsersController.new.send(:user_form_options_payload)
      refute_equal before, changed
      assert_includes changed[:village_options], "Changed Village"
      raise ActiveRecord::Rollback
    end
    assert_equal before, UsersController.new.send(:user_form_options_payload)
  end

  test "VRP attribute preserves escaped bytes and reuses them without hierarchy rebuild" do
    first = VrpsController.new
    expected = ERB::Util.html_escape(ERB::Util.json_escape(first.send(:location_hierarchy_mappings).to_json))
    assert_equal expected, first.send(:vrp_location_browser_attribute)
    warm = VrpsController.new
    warm.define_singleton_method(:location_hierarchy_mappings) { raise "Warm attribute must skip rebuilding" }
    actual = warm.send(:vrp_location_browser_attribute)
    assert_equal expected, actual
    assert_predicate actual, :html_safe?
    @record.update_columns(data: @record.data.merge("village_name" => "Changed Village"))
    assert_includes VrpsController.new.send(:vrp_location_browser_attribute), "Changed Village"
  end

  test "VRP label cache preserves uncached results filter keys and timestamp preserving edits" do
    first = VrpsController.new
    expected = first.send(:uncached_distinct_lg_directory_values, "village_name", "village", state: "State")
    assert_equal expected, first.send(:distinct_lg_directory_values, "village_name", "village", state: "State")
    warm = VrpsController.new
    warm.define_singleton_method(:uncached_distinct_lg_directory_values) { |*| raise "Warm labels must skip the directory scan" }
    result = warm.send(:distinct_lg_directory_values, "village_name", "village", state: "State")
    assert_equal expected, result
    result.clear
    assert_equal expected, warm.send(:distinct_lg_directory_values, "village_name", "village", state: "State")
    assert_empty VrpsController.new.send(:distinct_lg_directory_values, "village_name", "village", state: "Elsewhere")
    @record.update_columns(data: @record.data.merge("village_name" => "Changed Village"))
    assert_equal ["Changed Village"], VrpsController.new.send(:distinct_lg_directory_values, "village_name", "village", state: "State")
  end
  test "user cold fill cannot publish changed options under an older snapshot after rollback" do
    before = UsersController.new.send(:user_form_options_payload)
    Rails.cache.clear
    ModuleRecord.transaction(requires_new: true) do
      controller = UsersController.new
      original = controller.method(:build_user_form_options_payload)
      record = @record
      controller.define_singleton_method(:build_user_form_options_payload) do
        record.update_columns(data: record.data.merge("village_name" => "During Fill"))
        original.call
      end
      assert_includes controller.send(:user_form_options_payload)[:village_options], "During Fill"
      raise ActiveRecord::Rollback
    end
    assert_equal before, UsersController.new.send(:user_form_options_payload)
  end

  test "VRP cold attribute and projection fills cannot contaminate the rolled back snapshot" do
    before = VrpsController.new.send(:vrp_location_browser_attribute)
    Rails.cache.clear
    ModuleRecord.transaction(requires_new: true) do
      controller = VrpsController.new
      original = controller.method(:location_hierarchy_mappings)
      record = @record
      controller.define_singleton_method(:location_hierarchy_mappings) do
        record.update_columns(data: record.data.merge("village_name" => "During Fill"))
        original.call
      end
      assert_includes controller.send(:vrp_location_browser_attribute), "During Fill"
      raise ActiveRecord::Rollback
    end
    assert_equal before, VrpsController.new.send(:vrp_location_browser_attribute)
  end

  test "VRP cold label fill cannot contaminate an older snapshot" do
    before = VrpsController.new.send(:distinct_lg_directory_values, "village_name", "village")
    Rails.cache.clear
    ModuleRecord.transaction(requires_new: true) do
      controller = VrpsController.new
      original = controller.method(:uncached_distinct_lg_directory_values)
      record = @record
      controller.define_singleton_method(:uncached_distinct_lg_directory_values) do |*keys, **filters|
        record.update_columns(data: record.data.merge("village_name" => "During Fill"))
        original.call(*keys, **filters)
      end
      assert_equal ["During Fill"], controller.send(:distinct_lg_directory_values, "village_name", "village")
      raise ActiveRecord::Rollback
    end
    assert_equal before, VrpsController.new.send(:distinct_lg_directory_values, "village_name", "village")
  end

end
