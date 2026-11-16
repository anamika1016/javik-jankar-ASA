require "test_helper"

class TargetEntryCatalogueLoadingTest < ActionController::TestCase
  tests TargetMappingsController

  setup do
    @controller.define_singleton_method(:current_app_user) { { "id" => "1", "record_type" => "User", "user_type" => "admin" } }
  end

  test "entry HTML does not fetch unused block-wise office or block catalogues" do
    @controller.define_singleton_method(:filtered_office_fco_options) { raise "Unused Office List HTTP" }
    @controller.define_singleton_method(:office_block_options) { |_| raise "Unused Block catalogue" }
    get :index
    assert_response :success
    assert_select '[data-target-entry-mode] option[value="ics_wise"][selected]', 1
    assert_select '[data-target-mapping][data-block-fco-options="[]"][data-block-options-by-fco="{}"]', 1
  end

  test "block mode JSON still returns authoritative office and block values" do
    @controller.define_singleton_method(:filtered_office_fco_options) { [{ value: "1||Office", label: "Office" }] }
    @controller.define_singleton_method(:office_block_options) { |value| [{ value: "2||Block", label: "Block for #{value}" }] }
    @controller.define_singleton_method(:office_village_options) { |*| [] }
    @controller.define_singleton_method(:external_village_farmers_for) { |_| [] }
    get :vrp_mappings, params: { target_entry_mode: "block_wise", fco_id: "1||Office" }, format: :json
    assert_response :success
    payload = response.parsed_body
    assert_equal [{ "value" => "1||Office", "label" => "Office" }], payload["fco_options"]
    assert_equal [{ "value" => "2||Block", "label" => "Block for 1||Office" }], payload["block_options"]
    assert_empty payload["ics_options"]
  end
end
