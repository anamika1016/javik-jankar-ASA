require "test_helper"

class OtherTargetMatchingScalingTest < ActiveSupport::TestCase
  Target = Struct.new(:id, :vrp_id, :vrp, :month_name, :ics_id, :ics_name,
    :village_id, :village_name, :main_activity_name, :activity_name)
  Owner = Struct.new(:name, :user_name)

  setup do
    @controller = ModulesController.new
    @controller.define_singleton_method(:model_ready?) { |_| true }
    @targets = 500.times.map do |i|
      Target.new(i + 1, i, Owner.new("JJ #{i}", "login#{i}"), " September ",
        "ics#{i}", "ICS #{i}", "v#{i}", "Village #{i}", "Other Activity", "Soil")
    end
    set_targets(@targets)
  end

  def set_targets(targets)
    @controller.instance_variable_set(:@other_target_candidate_targets, targets)
    @controller.instance_variable_set(:@other_target_candidate_targets_by_id, targets.index_by { |t| t.id.to_s })
  end

  def record(owner:, month: "september", saved_id: nil, topic: "Other Activity", subject: "Soil")
    ModuleRecord.new(data: { "jeevika_jankar_id" => owner, "month" => month,
      "ics" => "ICS 12", "village" => "Village 12", "main_activity" => topic,
      "sub_activity" => subject, "target_mapping_id" => saved_id })
  end

  test "indexed matching preserves legacy aliases direct ids order and activity matching" do
    ["12", " JJ 12 ", "LOGIN12", "missing"].product([nil, "2", "missing"], ["Soil", "soil", "Different"]).each do |owner, saved, subject|
      data = record(owner: owner, saved_id: saved, subject: subject)
      direct = saved.present? && @targets.any? { |t| t.id.to_s == saved } ? [saved] : []
      expected = @targets.select do |target|
        @controller.send(:other_target_record_matches_target?, target, owner.strip.downcase,
          "september", "ics 12", "village 12", "other activity", subject.downcase)
      end.map { |t| t.id.to_s }
      assert_equal (direct + expected).uniq, @controller.send(:other_target_record_target_mapping_ids, data)
    end
  end

  test "matching examines only the selected owner and month after indexing" do
    calls = 0
    original = @controller.method(:other_target_record_matches_target?)
    @controller.define_singleton_method(:other_target_record_matches_target?) do |*args|
      calls += 1
      original.call(*args)
    end
    10.times { assert_equal ["13"], @controller.send(:other_target_record_target_mapping_ids, record(owner: "12")) }
    assert_equal 10, calls, "500 targets should not be scanned for each saved record"
  end

  test "lookup follows bill scope changes and empty candidates" do
    assert_equal ["13"], @controller.send(:other_target_record_target_mapping_ids, record(owner: "12"))
    set_targets([@targets.first])
    assert_empty @controller.send(:other_target_record_target_mapping_ids, record(owner: "12"))
    set_targets([])
    assert_equal ["legacy"], @controller.send(:other_target_record_target_mapping_ids, record(owner: "12", saved_id: "legacy"))
    set_targets(@targets)
    assert_equal ["13"], @controller.send(:other_target_record_target_mapping_ids, record(owner: "12"))
  end
end
