require "test_helper"

# Farmers are fetched one village at a time, so a blank village in the API
# response can always be recovered from the village that was asked for.
class TargetMappingVillageFallbackTest < ActiveSupport::TestCase
  setup do
    @controller = TargetMappingsController.new
    Rails.cache.clear
  end

  teardown { Rails.cache.clear }

  def stub_api_rows(rows)
    @controller.define_singleton_method(:fetch_external_farmers) { |**| rows }
  end

  test "blank village names fall back to the selected village label" do
    ["-", "", nil, "NULL", "n/a"].each do |api_value|
      Rails.cache.clear
      stub_api_rows([{ id: "1", farmer_name: "Anita Majhi", father_name: "Ananta Majhi",
                       tracenet_no: "OR2606014862", village_name: api_value }])

      rows = @controller.send(:external_village_farmers_for, ["5558||Borbhatta"])

      assert_equal "Borbhatta", rows.first[:village_name],
        "expected the selected village to replace #{api_value.inspect}"
    end
  end

  test "a real village name from the API is never overwritten" do
    stub_api_rows([{ id: "1", farmer_name: "Anita Majhi", village_name: "ApiVillage" }])

    rows = @controller.send(:external_village_farmers_for, ["5558||Borbhatta"])

    assert_equal "ApiVillage", rows.first[:village_name]
  end

  test "each village keeps its own label when several are selected" do
    @controller.define_singleton_method(:fetch_external_farmers) do |**kwargs|
      [{ id: "f#{kwargs[:id]}", farmer_name: "Farmer #{kwargs[:id]}", village_name: "-" }]
    end

    rows = @controller.send(:external_village_farmers_for, ["5558||Borbhatta", "3929||Karlasoda"])

    assert_equal({ "f5558" => "Borbhatta", "f3929" => "Karlasoda" },
      rows.to_h { |row| [row[:id], row[:village_name]] })
  end

  test "an id with no label leaves the API value untouched" do
    stub_api_rows([{ id: "1", farmer_name: "Anita Majhi", village_name: "-" }])

    rows = @controller.send(:external_village_farmers_for, ["5558"])

    assert_equal "-", rows.first[:village_name]
  end
end
