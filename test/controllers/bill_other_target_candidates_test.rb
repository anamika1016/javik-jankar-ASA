require "test_helper"

class BillOtherTargetCandidatesTest < ActiveSupport::TestCase
  Owner = Struct.new(:name, :user_name)
  Target = Struct.new(:id, :vrp_id, :vrp, :month_name, :ics_id, :ics_name,
    :village_id, :village_name, :main_activity_name, :activity_name)

  test "indexed candidates preserve full matching output and source order across owner scopes" do
    first = Target.new(71, 81, Owner.new("First Person", "first_login"), "October", "I", "ICS", "V", "Village", "Other", "Work")
    second = Target.new(72, 82, Owner.new("Second Person", "second_login"), "October", "I", "ICS", "V", "Village", "Other", "Work")
    records = [
      row(1, "target_mapping_id" => " 71 "),
      row(2, metadata(first).merge("target_mapping_id" => "missing")),
      row(3, metadata(first).merge("jeevika_jankar_id" => nil, "jeevika_jankar_name" => " FIRST PERSON ")),
      row(4, metadata(second)),
      row(5, metadata(first).merge("target_mapping_id" => "72")),
      row(6, "target_mapping_id" => "unrelated"),
      row(7, metadata(first).merge("ics" => nil)),
      row(8, metadata(first).merge("jeevika_jankar_id" => "first_login")),
      row(9, metadata(first).merge("month" => "September", "target_mapping_id" => "71")),
      row(10, metadata(first).merge("jeevika_jankar_id" => "unrelated", "select_vrp" => "81"))
    ]
    records.insert(3, records.first) # Duplicate source rows must survive.
    c = calculator
    [[first], [second], [first, second], [], [first]].each do |targets|
      set_targets(c, targets)
      expected = records.flat_map { |r| c.send(:other_target_record_target_mapping_ids, r).map { |id| [r.id, id] } }
      candidates = c.send(:other_target_calculation_candidates, records)
      actual = candidates.flat_map { |r| c.send(:other_target_record_target_mapping_ids, r).map { |id| [r.id, id] } }
      assert_equal expected, actual
      assert_equal records, candidates if targets.empty?
      assert_operator candidates.length, :<, records.length if targets == [second]
    end
    assert_equal 1, c.instance_variable_get(:@other_target_calculation_record_indexes).size
  end

  test "achievement totals and completed farmer IDs match unfiltered processing" do
    target = Target.new(71, 81, Owner.new("First Person", "first_login"), "October", "I", "ICS", "V", "Village", "Other", "Work")
    records = %w[Approved Active Pending Returned Rejected Inactive].each_with_index.map do |status, i|
      row(i + 1, metadata(target).merge("approval_status" => status, "achievement" => "#{i + 1}",
        "achievement_date" => "2026-10-10", "selected_farmer_ids" => ["#{i}", "shared"]))
    end
    records << row(20, "target_mapping_id" => "71", "achievement" => "2", "selected_farmer_ids" => ["legacy"])
    records << row(21, metadata(target).merge("deleted" => true, "achievement" => "99"))
    records << row(22, "target_mapping_id" => "unrelated", "achievement" => "500")
    baseline = calculator
    baseline.define_singleton_method(:other_target_calculation_candidates) { |rows| rows }
    optimized = calculator
    [baseline, optimized].each do |c|
      set_targets(c, [target])
      c.define_singleton_method(:other_target_records_for_calculation) { |_| records }
    end
    assert_equal baseline.send(:approved_other_target_achievement_index), optimized.send(:approved_other_target_achievement_index)
    assert_equal baseline.send(:approved_other_target_completed_farmer_ids_by_target), optimized.send(:approved_other_target_completed_farmer_ids_by_target)
    assert_equal 5.0, optimized.send(:approved_other_target_achievement_index).dig("71", :achievement)
    assert_equal %w[0 shared 1 legacy], optimized.send(:approved_other_target_completed_farmer_ids_by_target)["71"]
  end

  test "CC label preserves precedence and skips item scans when the primary label is present" do
    c = calculator
    owner = Struct.new(:cluster_incharge).new(" Mapped CC ")
    c.define_singleton_method(:jeevika_bill_vrp) { |_| owner }
    bill = row(1, "cluster_incharge" => "Saved CC", "cc_name" => "Saved fallback")
    c.define_singleton_method(:jeevika_bill_detail_rows) { |_| raise "Unused bill items" }
    assert_equal "Mapped CC", c.send(:jeevika_bill_cc_name, bill)
    owner.cluster_incharge = "null"
    assert_equal "Saved CC", c.send(:jeevika_bill_cc_name, bill)
    bill.data["cluster_incharge"] = " NIL "
    bill.data["cc_name"] = "-"
    c.define_singleton_method(:jeevika_bill_detail_rows) do |_|
      [{ "cluster_incharge" => "-", "cc_name" => "First item" }, { "cluster_incharge" => "Later item" }]
    end
    assert_equal "First item", c.send(:jeevika_bill_cc_name, bill)
    c.define_singleton_method(:jeevika_bill_detail_rows) { |_| [] }
    assert_equal "-", c.send(:jeevika_bill_cc_name, bill)
  end

  test "empty monthly submissions do not load target owners or build indexes" do
    c = calculator
    c.define_singleton_method(:other_target_candidate_targets) { raise "Unused target lookup" }
    rows = []
    assert_same rows, c.send(:other_target_calculation_candidates, rows)
    assert_nil c.instance_variable_get(:@other_target_calculation_record_indexes)
  end

  private

  def calculator
    ModulesController.new.tap { |c| c.define_singleton_method(:model_ready?) { |_| true } }
  end

  def set_targets(controller, targets)
    controller.instance_variable_set(:@other_target_candidate_targets, targets)
    controller.instance_variable_set(:@other_target_candidate_targets_by_id, targets.index_by { |t| t.id.to_s })
  end

  def metadata(target)
    { "jeevika_jankar_id" => target.vrp_id.to_s, "month" => "October", "ics" => "I", "village" => "V",
      "training_topic" => "Other", "training_subject" => "Work" }
  end

  def row(id, data)
    ModuleRecord.new(id: id, module_slug: "other-target", updated_at: Time.utc(2026, 10, 10), data: data)
  end
end
