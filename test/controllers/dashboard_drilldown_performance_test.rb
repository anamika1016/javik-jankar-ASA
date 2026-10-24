require "test_helper"

class DashboardDrilldownPerformanceTest < ActiveSupport::TestCase
  test "location and mapping lists preserve payloads without calculating achievements" do
    controller = ModulesController.new
    controller.define_singleton_method(:vrp_dashboard_target_progress_rows) { |*| raise "Unused achievement scan" }
    controller.define_singleton_method(:vrp_dashboard_farmer_status_sets) { |*| raise "Unused farmer status scan" }
    farmer_rows = [["ICS", "Village", "Farmer", "Father", "Trace"]]
    controller.define_singleton_method(:vrp_dashboard_mapped_farmer_rows) { |*args, **kwargs| farmer_rows }
    controller.define_singleton_method(:vrp_dashboard_afl_farmer_rows_for_target_villages) { |*| farmer_rows }
    controller.define_singleton_method(:vrp_dashboard_village_rows) do |*|
      [{ fco: "FCO", village: "Village", farmers: 3, targets: 2, target_quantity: 4 }]
    end
    controller.define_singleton_method(:vrp_dashboard_target_farmer_payload) { |*| { selected: "target farmers" } }

    %w[mapped_farmers mapped_village_farmers ics_mapped_farmers].each do |key|
      payload = controller.send(:vrp_dashboard_detail_payload, key, nil, [], [], [])
      assert_equal farmer_rows, payload[:rows]
      assert_equal 1, payload[:total]
      assert_equal key, payload[:key]
    end
    village = controller.send(:vrp_dashboard_detail_payload, "mapped_villages", nil, [], [], [])
    assert_equal [["FCO", "Village", 3, 2, 4]], village[:rows]
    assert_equal({ selected: "target farmers" }, controller.send(:vrp_dashboard_detail_payload, "target_farmers", nil, [], [], []))
    %w[assigned_farmers assigned_target pending_target achieved_target main_activities sub_activities].each do |key|
      assert controller.send(:vrp_dashboard_detail_uses_progress?, key)
    end
  end

  test "progress reads preserve matching approval totals and farmers without image payloads" do
    data = {
      "target_mapping_id" => "901", "month" => "October", "achievement" => "2.5",
      "achievement_date" => "2026-10-02", "approval_status" => "Final Approved",
      "selected_farmer_ids" => ["1", 2, "1"], "deleted" => false,
      "photo_front_view" => ["x" * 100_000], "unrelated_metadata" => { "large" => "x" * 100_000 }
    }
    record = ModuleRecord.create!(module_slug: "other-target", data: data)
    target = Struct.new(:id, :month_name).new(901, "October")
    calculate = lambda do |full|
      c = ModulesController.new
      c.instance_variable_set(:@other_target_candidate_targets, [target])
      if full
        c.define_singleton_method(:other_target_progress_records_scope) { ModuleRecord.where(module_slug: ModulesController::OTHER_TARGET_MODULE_SLUGS) }
      end
      [c.send(:approved_other_target_achievement_index), c.send(:approved_other_target_completed_farmer_ids_by_target).to_h]
    end
    assert_equal calculate.call(true), calculate.call(false)
    assert_equal 2.5, calculate.call(false).first.dig("901", :achievement)
    projected = ModulesController.new.send(:other_target_progress_records_scope).find(record.id)
    assert_equal ["1", 2, "1"], projected.data["selected_farmer_ids"]
    assert_not projected.data.key?("photo_front_view")
    assert_operator projected.data.to_json.bytesize, :<, data.to_json.bytesize / 100
    assert projected.readonly?
    assert_equal data, record.reload.data
  end
end
