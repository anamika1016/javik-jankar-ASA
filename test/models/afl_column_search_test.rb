require "test_helper"

# Per-header search on the AFL Upload list: one box under each column heading.
class AflColumnSearchTest < ActiveSupport::TestCase
  setup do
    Afl.delete_all
    @odisha = Afl.create!(id: 90_001, fco: "Bhawanipatna", fco_id: "995",
      ics_name: "Gurjimunda", farmer_name: "Ram Kumar", status: "Active", tracenet_no: "TN-1")
    @mp = Afl.create!(id: 90_002, fco: "Sausar", fco_id: "1004",
      ics_name: "Ambada", farmer_name: "Ram Singh", status: "Inactive", tracenet_no: "TN-2")
  end

  test "a single filter narrows to that column only" do
    assert_equal [@odisha.id], Afl.column_search("fco" => "Bhawanipatna").pluck(:id)
    # "Ram" is in both farmer names but only one fco.
    assert_equal [@odisha.id, @mp.id].sort, Afl.column_search("farmer_name" => "Ram").pluck(:id).sort
  end

  test "several filters narrow each other rather than widening" do
    assert_equal [@odisha.id],
      Afl.column_search("farmer_name" => "Ram", "fco" => "Bhawanipatna").pluck(:id)
    assert_empty Afl.column_search("farmer_name" => "Ram", "fco" => "Nowhere")
  end

  test "matching is partial and case-insensitive, like the single search box" do
    assert_equal [@odisha.id], Afl.column_search("fco" => "bhawani").pluck(:id)
    assert_equal [@odisha.id], Afl.column_search("ics_name" => "GURJI").pluck(:id)
  end

  # id and the numeric/date columns are not text, so they are compared as the
  # row displays them rather than by a typed comparison that would raise.
  test "non-text columns are searchable by what the row shows" do
    assert_equal [@odisha.id], Afl.column_search("id" => "90001").pluck(:id)
    assert_equal [@odisha.id, @mp.id].sort, Afl.column_search("id" => "9000").pluck(:id).sort
  end

  test "blank values are ignored so an empty box does not hide every row" do
    assert_equal 2, Afl.column_search("fco" => "", "farmer_name" => "  ").count
    assert_equal 2, Afl.column_search({}).count
    assert_equal 2, Afl.column_search(nil).count
  end

  # Only the columns the table shows may be filtered; anything else in the
  # query string is ignored rather than reaching the database.
  test "a column the list does not show is not searchable" do
    assert_equal 2, Afl.column_search("aadhar" => "123").count
    assert_equal 2, Afl.column_search("updated_at" => "2026").count
    assert_equal [@odisha.id], Afl.column_search("aadhar" => "123", "fco" => "Bhawanipatna").pluck(:id)
  end

  test "a value containing LIKE wildcards is matched literally" do
    literal = Afl.create!(id: 90_003, farmer_name: "100% Organic")
    assert_equal [literal.id], Afl.column_search("farmer_name" => "100%").pluck(:id)
    assert_empty Afl.column_search("farmer_name" => "%%%%%%")
  end

  test "column search composes with the single search box" do
    assert_equal [@odisha.id],
      Afl.search("Ram").column_search("fco" => "Bhawanipatna").pluck(:id)
  end

  # Each comparison offered in a header's dropdown.
  test "equals matches the whole value, not part of it" do
    assert_equal [@odisha.id], Afl.column_search({ "fco" => "Bhawanipatna" }, { "fco" => "equals" }).pluck(:id)
    assert_empty Afl.column_search({ "fco" => "hawanipat" }, { "fco" => "equals" })
  end

  test "starts with and ends with anchor to their end" do
    assert_equal [@odisha.id], Afl.column_search({ "fco" => "Bhawa" }, { "fco" => "starts_with" }).pluck(:id)
    assert_empty Afl.column_search({ "fco" => "patna" }, { "fco" => "starts_with" })
    assert_equal [@odisha.id], Afl.column_search({ "fco" => "patna" }, { "fco" => "ends_with" }).pluck(:id)
    assert_empty Afl.column_search({ "fco" => "Bhawa" }, { "fco" => "ends_with" })
  end

  # A row with nothing in the column does not show the text either, so it
  # belongs in "does not contain" rather than being dropped by NOT ILIKE.
  test "does not contain keeps rows whose column is blank" do
    blank = Afl.create!(id: 90_004, farmer_name: "No FCO", fco: nil)
    ids = Afl.column_search({ "fco" => "Bhawanipatna" }, { "fco" => "not_contains" }).pluck(:id)
    assert_includes ids, @mp.id
    assert_includes ids, blank.id
    assert_not_includes ids, @odisha.id
  end

  test "is empty and is not empty split the rows between them" do
    Afl.create!(id: 90_005, farmer_name: "Blank status", status: "")
    Afl.create!(id: 90_006, farmer_name: "Null status", status: nil)
    empty = Afl.column_search({}, { "status" => "empty" }).pluck(:id)
    filled = Afl.column_search({}, { "status" => "not_empty" }).pluck(:id)

    assert_equal [90_005, 90_006].sort, empty.sort
    assert_equal [@odisha.id, @mp.id].sort, filled.sort
    assert_equal Afl.count, empty.size + filled.size
  end

  test "an unknown comparison falls back to contains rather than failing" do
    assert_equal [@odisha.id], Afl.column_search({ "fco" => "awani" }, { "fco" => ";DROP TABLE afls" }).pluck(:id)
  end

  test "every heading the list renders can be searched by" do
    Afl::LIST_HEADERS.each_key do |column|
      # A heading whose column cannot be queried -- wrong name, or a type the
      # ::text cast does not cover -- would raise here rather than quietly
      # returning every row.
      matched = Afl.column_search(column => "definitely-not-present").count
      assert_equal 0, matched, "#{column} must filter, not be ignored"
    end
  end
end
