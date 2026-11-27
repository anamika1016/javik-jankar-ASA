require "test_helper"

# The ID in the uploaded file is the row's ID. Excel hands the same number over
# in several shapes depending on how the cell was typed, and every one of them
# has to land as that exact ID -- a row that comes back under a different ID is
# unfindable by the number the uploader has in their sheet.
class AflImportIdTest < ActiveSupport::TestCase
  HEADERS = ["ID", "Farmer_Name"].freeze

  setup { Afl.delete_all }

  test "a plain integer ID is kept exactly" do
    Afl.import_rows([["178203", "Ram"]], HEADERS)
    assert_equal [178_203], Afl.pluck(:id)
  end

  # A numeric Excel cell arrives as a Float, and "178203.0" is not an integer
  # string -- the row was skipped or renumbered rather than kept as 178203.
  test "a numeric cell carrying a whole number is kept as that number" do
    result = Afl.import_rows([[178_203.0, "Ram"]], HEADERS)
    assert_equal [178_203], Afl.pluck(:id), "skipped: #{result[:skipped].inspect}"
  end

  test "an integer cell is kept as that number" do
    Afl.import_rows([[178_203, "Ram"]], HEADERS)
    assert_equal [178_203], Afl.pluck(:id)
  end

  # Large IDs in a numeric column are written in scientific notation by Excel.
  test "a scientific notation cell is kept as the number it denotes" do
    result = Afl.import_rows([["1.78203E5", "Ram"]], HEADERS)
    assert_equal [178_203], Afl.pluck(:id), "skipped: #{result[:skipped].inspect}"
  end

  test "surrounding spaces do not change the ID" do
    Afl.import_rows([["  178203  ", "Ram"]], HEADERS)
    assert_equal [178_203], Afl.pluck(:id)
  end

  test "the imported row is findable by the ID the sheet had" do
    Afl.import_rows([[178_203.0, "Ram"]], HEADERS)
    assert_equal 1, Afl.column_search("id" => "178203").count,
      "searching the sheet's ID must find the row it created"
  end

  # A row whose ID is not a whole number has no business silently becoming one.
  test "a fractional ID is skipped rather than rounded into a different row" do
    result = Afl.import_rows([["178203.75", "Ram"]], HEADERS)
    assert_empty Afl.all
    assert_equal 1, result[:skipped].size
  end

  test "a non-numeric ID is skipped" do
    result = Afl.import_rows([["ABC", "Ram"]], HEADERS)
    assert_empty Afl.all
    assert_equal 1, result[:skipped].size
  end

  test "later inserts do not reuse an imported ID" do
    Afl.import_rows([[178_203.0, "Ram"]], HEADERS)
    fresh = Afl.create!(farmer_name: "Next")
    assert_operator fresh.id, :>, 178_203
  end
end
