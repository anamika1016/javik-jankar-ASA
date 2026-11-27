require "test_helper"

class TrainingOwnerNormalizationCacheTest < ActiveSupport::TestCase
  test "repeated owner comparisons reuse normalization without sharing mutable results" do
    controller = ModulesController.new
    record = ModuleRecord.new(data: { "jeevika_jankar_id" => " 12 ", "trainer_name" => " Owner " })
    owner = Vrp.new(id: 12, name: "Owner", mobile_no: "123")
    calls = 0
    original = controller.method(:normalize_dashboard_text)
    controller.define_singleton_method(:normalize_dashboard_text) { |value| calls += 1; original.call(value) }
    100.times { assert controller.send(:training_record_vrp_scope_matches?, record, owner) }
    assert_operator calls, :<=, 12

    values = controller.send(:training_record_owner_values, record)
    values.first.replace("Changed result")
    values.clear
    assert_equal ["12", "owner"], controller.send(:training_record_owner_values, record)
    vrp_values = controller.send(:training_vrp_owner_values, owner)
    vrp_values.first.replace("Changed result")
    assert_equal "12", controller.send(:training_vrp_owner_values, owner).first
  end

  test "in-place input edits and different objects with the same id retain exact ownership rules" do
    controller = ModulesController.new
    record = ModuleRecord.new(id: 1, data: { "trainer_name" => "Owner" })
    owner = Vrp.new(id: 12, name: "Owner", mobile_no: "123")
    assert controller.send(:training_record_vrp_scope_matches?, record, owner)
    owner.name.replace("Renamed")
    refute controller.send(:training_record_vrp_scope_matches?, record, owner)
    record.data["trainer_name"].replace("Renamed")
    assert controller.send(:training_record_vrp_scope_matches?, record, owner)
    other = ModuleRecord.new(id: 1, data: { "trainer_name" => "Different" })
    refute controller.send(:training_record_vrp_scope_matches?, other, owner)
    assert controller.send(:training_record_vrp_scope_matches?, ModuleRecord.new(data: {}), owner)
    assert controller.send(:training_record_vrp_scope_matches?, record, nil)
  end
end
