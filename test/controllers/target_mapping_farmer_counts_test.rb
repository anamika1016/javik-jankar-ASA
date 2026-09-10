require "test_helper"

class TargetMappingFarmerCountsTest < Minitest::Test
  def test_count_endpoint_routes_and_returns_count_without_fetching_details
    route = Rails.application.routes.recognize_path("/target_mappings/village_farmers", method: :get)
    assert_equal "village_farmers", route[:action]
    controller = TargetMappingsController.new
    controller.request = ActionController::TestRequest.create(TargetMappingsController)
    controller.set_response!(ActionDispatch::TestResponse.new)
    controller.params = ActionController::Parameters.new(data_type: "short", village_ids: '["182","184"]')
    controller.define_singleton_method(:external_village_farmer_count_for) { |_villages| 35 }
    controller.define_singleton_method(:external_village_farmers_for) { |_villages| raise "Detail fetch must not delay count" }
    controller.village_farmers
    assert_equal 35, JSON.parse(controller.response.body)["count"]
  end

  def test_failed_count_is_not_reported_as_zero
    controller = TargetMappingsController.new
    controller.request = ActionController::TestRequest.create(TargetMappingsController)
    controller.set_response!(ActionDispatch::TestResponse.new)
    controller.params = ActionController::Parameters.new(data_type: "short", village_ids: '["182"]')
    controller.define_singleton_method(:external_village_farmer_count_for) { |_villages| nil }
    controller.village_farmers
    assert_equal 503, controller.response.status
    refute JSON.parse(controller.response.body).key?("count")
  end
end
