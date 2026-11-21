require "test_helper"

class ImmutableFormCatalogueTest < ActiveSupport::TestCase
  test "real form consumers preserve mutable request copies over an immutable store" do
    ModuleRecord.create!(module_slug: "village-master", data: { "state_name" => "Immutable State", "village_name" => "Immutable Village <&", "status" => "Active" })
    cache = ImmutableCatalogueStore.new(size: 32.megabytes)
    build = lambda do |type, getter|
      type.new.tap do |c|
        c.define_singleton_method(getter) { cache }
        c.define_singleton_method(:shared_form_catalogue_cache) { nil }
      end
    end
    first = build.call(ModulesController, :location_catalogue_cache).send(:location_hierarchy_mappings)
    first.first[:state].replace("Request-local state")
    second = build.call(ModulesController, :location_catalogue_cache).send(:location_hierarchy_mappings)
    assert_includes second.map { |row| row[:state] }, "Immutable State"
    attrs = build.call(ModulesController, :location_catalogue_cache).send(:cached_location_master_records, "village-master")
    attrs.first.data["village_name"].replace("Request-local village")
    assert_equal "Immutable Village <&", build.call(ModulesController, :location_catalogue_cache).send(:cached_location_master_records, "village-master").first.data["village_name"]
    [ [UsersController, :user_form_options_cache, :user_form_options_payload],
      [VrpsController, :vrp_location_catalogue_cache, :vrp_location_browser_attribute] ].each do |type, getter, reader|
      expected = build.call(type, getter).send(reader)
      actual = build.call(type, getter).send(reader)
      assert_equal expected, actual
      text = actual.is_a?(Hash) ? actual[:location_hierarchy_browser_attribute] : actual
      text.replace("Request-local attribute")
      assert_equal expected, build.call(type, getter).send(reader)
    end
  end
end
