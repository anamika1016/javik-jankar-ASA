require "test_helper"

class TargetMappingReadOnlyPerformanceTest < ActionController::TestCase
  tests TargetMappingsController

  setup do
    @controller.define_singleton_method(:current_app_user) do
      { "id" => "1", "record_type" => "User", "user_type" => "admin", "name" => "Admin" }
    end
    %i[target_vrps module_options target_sub_activity_map filtered_office_fco_options edit_payload target_sub_activity_options].each do |method|
      @controller.define_singleton_method(method) { |*| raise "Read-only list must not build entry form options" }
    end
  end

  test "recent target mappings render their table without loading hidden entry-form catalogues" do
    get :index, params: { list_only: "true" }
    assert_response :success
    assert_select "h1", text: "Recent Target Mappings"
    assert_select "[data-target-mapping]", count: 0
    assert_select "table", minimum: 1
  end

  test "read-only target export retains its existing spreadsheet response" do
    get :index, params: { list_only: "true", format: :xlsx }
    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type
    assert response.body.start_with?("PK")
  end
end
