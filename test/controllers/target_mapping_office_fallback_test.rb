require "test_helper"

class TargetMappingOfficeFallbackTest < ActiveSupport::TestCase
  test "unavailable office services return empty options instead of URL strings" do
    controller = TargetMappingsController.new
    controller.define_singleton_method(:office_list_api_urls) { ["https://example.test/offices"] }
    controller.define_singleton_method(:fetch_office_list_items) { |_url| [] }
    Rails.cache.clear
    assert_equal [], controller.send(:office_list_items)
    assert_equal [], controller.send(:office_list_fco_options)
  end
end
