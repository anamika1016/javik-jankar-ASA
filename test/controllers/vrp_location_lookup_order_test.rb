require "test_helper"

# active_records_for_location can be asked for several location masters at
# once, and gram_panchayat_name_lookup folds the result into a code -> label
# hash where the last write wins. The order the records arrive in therefore
# decides which label a code that appears in two masters resolves to.
#
# The preloaded path groups the records by slug; the fallback used to ask for
# every slug in one query ordered by created_at, which interleaves them. The
# two disagreed, so the same code resolved differently depending on whether the
# batch preload had already run. These tests pin one answer for both paths.
class VrpLocationLookupOrderTest < ActiveSupport::TestCase
  SHARED_CODE = "999".freeze

  setup do
    base = Time.zone.parse("2026-02-01 00:00:00")

    # The gram panchayat master is the older row, the LG directory the newer
    # one, so ordering by created_at puts them in the opposite order to
    # grouping by slug - which is what makes the two paths distinguishable.
    @gp_master = ModuleRecord.create!(module_slug: "gram-panchayat-master", data: {
      "gp_code" => SHARED_CODE, "gram_panchayat_name" => "GP Master Label",
      "state_name" => "MP", "district_name" => "Jhabua", "block_name" => "Ranapur"
    }, created_at: base, updated_at: base)

    @lg_row = ModuleRecord.create!(module_slug: "lg-directory-list", data: {
      "gp_code" => SHARED_CODE, "gram_panchayat" => "LG Directory Label",
      "state" => "MP", "district" => "Jhabua", "block" => "Ranapur"
    }, created_at: base + 1.hour, updated_at: base + 1.hour)

    @village = ModuleRecord.create!(module_slug: "village-master", data: {
      "village_name" => "Kalapan", "gram_panchayat_name" => "Village GP Label",
      "state_name" => "MP", "district_name" => "Jhabua", "block_name" => "Ranapur"
    }, created_at: base + 2.hours, updated_at: base + 2.hours)
  end

  def slug_order(controller)
    controller
      .send(:active_records_for_location, ["gram-panchayat-master", "lg-directory-list", "village-master"])
      .map { |record| ModuleRecord.where(id: record.id).pick(:module_slug) }
  end

  test "cold and preloaded paths return the masters in the same slug order" do
    cold = slug_order(VrpsController.new)

    warm_controller = VrpsController.new
    warm_controller.send(:preload_vrp_form_location_records!)
    warm = slug_order(warm_controller)

    assert_equal ["gram-panchayat-master", "lg-directory-list", "village-master"], cold
    assert_equal cold, warm,
      "the preloaded path and the fallback disagreed on order, so a shared code " \
      "would resolve to a different label depending on which ran"
  end

  test "a code carried by two masters resolves to the same label on both paths" do
    cold = VrpsController.new.send(:gram_panchayat_name_lookup)[SHARED_CODE]

    warm_controller = VrpsController.new
    warm_controller.send(:preload_vrp_form_location_records!)
    warm = warm_controller.send(:gram_panchayat_name_lookup)[SHARED_CODE]

    assert_equal "LG Directory Label", cold
    assert_equal cold, warm,
      "the same gram panchayat code resolved to a different label depending on " \
      "whether the batch preload had run"
  end

  test "asking for a single master is unaffected" do
    controller = VrpsController.new
    records = controller.send(:active_records_for_location, "gram-panchayat-master")
    assert_equal [@gp_master.id], records.map(&:id)
  end

  test "a warm preload still answers the grouped request without extra queries" do
    controller = VrpsController.new
    controller.send(:preload_vrp_form_location_records!)

    queries = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      queries << sql if sql.match?(/SELECT.*FROM "module_records"/m)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      controller.send(:active_records_for_location,
        ["gram-panchayat-master", "lg-directory-list", "village-master"])
    end

    assert_empty queries,
      "the grouped request re-queried masters the preload had already loaded"
  end
end
