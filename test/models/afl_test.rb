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
      [["90000101", "FARM-101", "Test Farmer"]],
      ["ID", "Farm_ID", "Farmer_Name"]
    )

    assert_equal 1, result[:imported]
    assert_equal "FARM-101", Afl.find(90000101).farm_id
  end

  test "rejects an AFL file without Farmer Name header" do
    error = assert_raises(ArgumentError) do
      Afl.import_rows([["FARM-101"]], ["Farm_ID"])
    end

    assert_equal "Excel is missing required header: Farmer_Name.", error.message
  end

  test "skips existing and repeated IDs without changing saved rows" do
    existing = Afl.create!(farmer_name: "Original")
    new_id = existing.id + 1000
    result = Afl.import_rows(
      [[existing.id, "Changed"], [new_id, "New"], [new_id, "Repeated"], ["", "Missing ID"]],
      ["ID", "Farmer_Name"]
    )

    assert_equal 1, result[:imported]
    assert_equal 2, result[:skipped].count { |row| row[:reason] == "ID already exists" }
    assert_equal 1, result[:skipped].count { |row| row[:reason] == "ID must be a positive integer" }
    assert_equal "Original", existing.reload.farmer_name
    assert_equal "New", Afl.find(new_id).farmer_name
    assert_operator Afl.create!(farmer_name: "Automatic ID").id, :>, new_id
  end

  test "rejects an AFL file without ID header" do
    error = assert_raises(ArgumentError) { Afl.import_rows([["Farmer"]], ["Farmer_Name"]) }
    assert_equal "Excel is missing required header: ID.", error.message
  end
end
