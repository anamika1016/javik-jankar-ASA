require "test_helper"

class AflTest < ActiveSupport::TestCase
  test "search matches fields outside the list table columns" do
    marker = SecureRandom.hex(6)
    afl = Afl.create!(
      farmer_name: "Farmer #{marker}",
      purchase_product_type: "Hidden #{marker}"
    )

    assert_includes Afl.search("Hidden #{marker}"), afl
  end

  test "imports farm id from Excel-style headers" do
    result = Afl.import_rows(
      [["FARM-101", "Test Farmer"]],
      ["Farm_ID", "Farmer_Name"]
    )

    assert_equal 1, result[:imported]
    assert_equal "FARM-101", Afl.order(:id).last.farm_id
  end

  test "rejects an AFL file without Farmer Name header" do
    error = assert_raises(ArgumentError) do
      Afl.import_rows([["FARM-101"]], ["Farm_ID"])
    end

    assert_equal "Excel is missing required header: Farmer_Name.", error.message
  end
end
