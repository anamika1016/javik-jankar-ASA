require "test_helper"

class TargetMappingCcTargetTest < ActiveSupport::TestCase
  test "CC target remains optional for existing records and is bounded by OPG" do
    target = TargetMapping.new(opg_training_target: 2)
    [nil, 0, 1, 2].each do |value|
      target.cc_target = value
      target.valid?
      assert_empty target.errors[:cc_target]
    end
    [-1, 0.5, 3].each do |value|
      target.cc_target = value
      target.valid?
      assert target.errors[:cc_target].any?
    end
    target.opg_training_target = nil
    target.cc_target = 1
    target.valid?
    assert target.errors[:cc_target].any?
  end

  test "CC survives save and edit payload without changing activity targets" do
    vrp = Vrp.new(name: "CC Test")
    vrp.assign_attributes(aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "performance@example.test",
      experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
      mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    target = TargetMapping.create!(vrp: vrp, fco_id: "FCO", ics_id: "ICS", village_id: "Village",
      month_name: "September", main_activity_name: "Training", activity_name: "OPG Training",
      target_quantity: 4, opg_training_target: 4, cc_target: 3)
    assert_equal 3, target.reload.cc_target
    assert_equal 4, target.target_quantity
    controller = TargetMappingsController.new
    assert_equal "3", controller.send(:edit_payload, target).dig(:training_targets, "cc")
  end
end
