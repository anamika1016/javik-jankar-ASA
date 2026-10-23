require "test_helper"

# module_records.data is a text column, so nothing stops a row from holding a
# JSON scalar or array instead of an object. The active-record filters that run
# before the key projections use ->>, which tolerates a scalar and lets such a
# row through - and then jsonb_each raises "cannot call jsonb_each on a
# non-object", taking down the whole screen rather than that one row.
#
# Every projection is now guarded with jsonb_typeof, the way the rest of the
# app guards its set-returning JSON calls. These tests check that a malformed
# row no longer breaks the page, and that well-formed rows are unaffected.
class JsonbProjectionMalformedDataTest < ActiveSupport::TestCase
  def good_village
    ModuleRecord.create!(module_slug: "village-master", data: {
      "state_name" => "Madhya Pradesh", "district_name" => "Jhabua",
      "block_name" => "Ranapur", "gram_panchayat_name" => "Bhilbarodi",
      "village_name" => "Kalapan", "village_id" => "V-1"
    })
  end

  # A JSON string and a JSON array both pass `presence` and both reach the
  # projection, and jsonb_each rejects each of them.
  def malformed_rows(slug)
    [
      ModuleRecord.create!(module_slug: slug, data: "corrupted-scalar"),
      ModuleRecord.create!(module_slug: slug, data: ["corrupted", "array"])
    ]
  end

  test "stored malformed rows really are non-objects at the database level" do
    rows = malformed_rows("village-master")
    types = ModuleRecord.where(id: rows.map(&:id))
      .pluck(Arel.sql("jsonb_typeof(data::jsonb)"))
      .sort
    assert_equal ["array", "string"], types,
      "the fixture must reproduce the shape that makes jsonb_each raise"
  end

  test "module location projection survives a malformed row and keeps the good ones" do
    good = good_village
    malformed_rows("village-master")

    controller = ModulesController.new
    records = nil
    assert_nothing_raised do
      controller.send(:preload_location_records!, ModulesController::LOCATION_MODULE_SLUGS)
      records = controller.send(:active_records_for_location, "village-master")
    end

    assert_includes records.map(&:id), good.id
    kept = records.find { |record| record.id == good.id }
    assert_equal "Kalapan", kept.data["village_name"]
    assert_equal "Bhilbarodi", kept.data["gram_panchayat_name"]
  end

  test "module location hierarchy still builds with a malformed row present" do
    good_village
    malformed_rows("village-master")

    rows = nil
    assert_nothing_raised { rows = ModulesController.new.send(:location_hierarchy_mappings) }
    assert rows.any? { |row| row[:village] == "Kalapan" }
  end

  test "Jeevika Jankar form location options survive a malformed row" do
    good = good_village
    malformed_rows("village-master")

    controller = VrpsController.new
    assert_nothing_raised { controller.send(:preload_vrp_form_location_records!) }
    records = controller.send(:active_records_for_location, "village-master")

    assert_includes records.map(&:id), good.id
    assert_equal "Kalapan", records.find { |r| r.id == good.id }.data["village_name"]
  end

  test "bill key projection survives a malformed bill row" do
    good = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => "77", "bill_month" => "October"
    })
    malformed_rows("jeevika-jankar-bill-process")

    controller = ModulesController.new
    controller.request = ActionDispatch::TestRequest.create

    keys = nil
    assert_nothing_raised { keys = controller.send(:jeevika_jankar_existing_bill_keys) }
    kept = keys.find { |row| row[:id] == good.id.to_s }
    assert kept, "the well-formed bill row must still come back"
    assert_equal "77", kept[:vrp_id]
    assert_equal "October", kept[:month]
    # The malformed rows project to {}, so they carry no vrp/month and are
    # dropped by the existing reject rather than blocking a duplicate bill.
    assert_equal 1, keys.size
  end

  test "bill summary projection survives a malformed bill row" do
    good = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => "77", "bill_month" => "October",
      "bill_items" => [{ "amount" => "100", "farmer_details" => { "dropped" => true } }]
    })
    malformed_rows("jeevika-jankar-bill-process")

    rows = nil
    controller = ModulesController.new
    assert_nothing_raised do
      scope = controller.send(:bill_summary_scope,
        ModuleRecord.where(module_slug: "jeevika-jankar-bill-process"))
      rows = scope.to_a
    end

    kept = rows.find { |row| row.id == good.id }
    assert kept, "the well-formed bill row must still come back"
    assert_equal "October", kept.data["bill_month"]
    # The projection's own purpose is still served: nested farmer detail is
    # dropped from the list payload.
    assert_not_includes kept.data.to_json, "dropped"
  end
end
