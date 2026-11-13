require "test_helper"
require_relative "../support/farmer_api_stubs"

# Farmers who logged in before the state column existed have no state, so
# they only ever receive All States posts. The backfill repairs them without
# asking every farmer to log in again.
class FarmerBackfillPlacesTest < ActiveSupport::TestCase
  include FarmerApiStubs

  FARMER = {
    "id" => 5, "full_name" => "Pooja", "mobile_no" => "7898071513",
    "aadhaar_no" => "111122223333",
    "land_details" => [{ "state_id" => 1, "district_id" => 36, "block_id" => 90, "village_id" => 10143 }]
  }.freeze

  test "a farmer with no state gets one, so state-wise posts reach them" do
    login = FarmerAppLogin.record_login!(farmer: FARMER, identifier_type: "mobile")
    login.update_columns(state_id: nil, state_name: nil, village_name: nil, district_name: nil)

    AsaLocationNames.stub_names(state: { "1" => "Madhya Pradesh" }, village: { "10143" => "KACHARI" }) do
      stub_farmer_apis(farmer: FARMER) { run_backfill }
    end

    login.reload
    assert_equal "1", login.state_id, "state_id is what decides who a post reaches"
    assert_equal "Madhya Pradesh", login.state_name
    assert_equal "KACHARI", login.village_name
  end

  test "a farmer the register has no land for is left alone, not half-written" do
    login = FarmerAppLogin.record_login!(farmer: FARMER.merge("land_details" => []),
      identifier_type: "mobile")
    login.update_columns(state_id: nil, state_name: nil)

    stub_farmer_apis(farmer: FARMER.merge("land_details" => [])) { run_backfill }

    assert_nil login.reload.state_id
  end

  test "a state already recorded is not overwritten" do
    login = FarmerAppLogin.record_login!(farmer: FARMER, identifier_type: "mobile")
    login.update_columns(state_id: "8", state_name: "Odisha", village_name: nil)

    AsaLocationNames.stub_names(state: { "1" => "Madhya Pradesh" }) do
      stub_farmer_apis(farmer: FARMER) { run_backfill }
    end

    assert_equal "8", login.reload.state_id
    assert_equal "Odisha", login.state_name
  end

  private

  def run_backfill
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("farmer_app_logins:backfill_places")
    Rake::Task["farmer_app_logins:backfill_places"].reenable

    original = $stdout
    $stdout = StringIO.new
    begin
      Rake::Task["farmer_app_logins:backfill_places"].invoke
    ensure
      $stdout = original
    end
  end
end
