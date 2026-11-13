require "test_helper"
require_relative "../support/farmer_api_stubs"

# The register answers a mobile lookup without land_details and an Aadhaar
# lookup with them. Land is where a farmer's state comes from, and the state
# decides which news and videos reach them -- so every farmer who signed in
# with their mobile ended up with no state at all.
class FarmerRegisterLandLookupTest < ActiveSupport::TestCase
  LEAN = {
    "id" => 5, "full_name" => "Pooja", "mobile_no" => "7898071513",
    "aadhaar_card_no" => "111122223333", "tracenet_id" => "MP2001415600"
  }.freeze
  LAND = [{ "state_id" => 1, "district_id" => 36, "block_id" => 90, "village_id" => 10143 }].freeze

  test "a mobile lookup with no land asks again by the Aadhaar it was given" do
    with_register_by_identifier(
      mobile: LEAN,
      aadhaar: LEAN.merge("land_details" => LAND)
    ) do
      farmer = FarmerRegisterLookup.by_mobile("7898071513").farmer

      assert_equal 1, Array(farmer["land_details"]).size
      assert_equal 1, farmer.dig("land_details", 0, "state_id")
      # The mobile answer's own fields survive the merge.
      assert_equal "MP2001415600", farmer["tracenet_id"]
    end
  end

  test "the state reaches the login record, so state-wise posts can find them" do
    with_register_by_identifier(mobile: LEAN, aadhaar: LEAN.merge("land_details" => LAND)) do
      lookup = FarmerRegisterLookup.by_mobile("7898071513")
      login = FarmerAppLogin.record_login!(farmer: lookup.farmer, identifier_type: "mobile")

      assert_equal "1", login.state_id
    end
  end

  test "a mobile lookup that already has land is not asked twice" do
    calls = []
    with_register_by_identifier(mobile: LEAN.merge("land_details" => LAND), aadhaar: LEAN, calls: calls) do
      FarmerRegisterLookup.by_mobile("7898071513")
    end

    assert_equal 1, calls.size, "no second call when the first answer was complete"
  end

  test "no Aadhaar in the answer means the lean record is used as-is" do
    bare = LEAN.except("aadhaar_card_no")
    with_register_by_identifier(mobile: bare, aadhaar: bare) do
      farmer = FarmerRegisterLookup.by_mobile("7898071513").farmer

      assert_equal "Pooja", farmer["full_name"]
      assert_empty Array(farmer["land_details"])
    end
  end

  test "an Aadhaar lookup is never asked a second time" do
    calls = []
    with_register_by_identifier(mobile: LEAN, aadhaar: LEAN, calls: calls) do
      FarmerRegisterLookup.by_aadhaar("111122223333")
    end

    assert_equal 1, calls.size
  end

  private

  # Answers differently depending on which identifier the request carried,
  # which is the whole behaviour under test.
  def with_register_by_identifier(mobile:, aadhaar:, calls: [])
    Rails.cache.clear
    FarmerRegisterLookup.class_eval do
      alias_method :__original_get, :get
      define_method(:get) do |uri|
        calls << uri.query
        farmer = uri.query.to_s.include?("aadhaar_no") ? aadhaar : mobile
        response = Net::HTTPOK.new("1.1", "200", "OK")
        body = { "status" => true, "result" => farmer }.to_json
        response.define_singleton_method(:body) { body }
        response
      end
    end

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
    FarmerRegisterLookup.class_eval do
      remove_method :get
      alias_method :get, :__original_get
      remove_method :__original_get
      private :get
    end
  end
end
