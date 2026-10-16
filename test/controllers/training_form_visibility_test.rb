require "test_helper"

class TrainingFormVisibilityTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    def @controller.admin_dashboard_user?; false; end
    def @controller.vrp_login_user?; false; end
    def @controller.current_app_user; { "username" => "ashvin" }; end
    def @controller.module_cluster_incharge_login?; true; end
    def @controller.current_cluster_incharge_labels; ["Ashvin Durve", "ashvin"]; end
  end

  test "training visibility follows the registered CC, not a similar name" do
    record = ModuleRecord.new(module_slug: "training-form", data: { "month" => "July" })
    @controller.instance_variable_set(:@visibility_vrp, Vrp.new(cluster_incharge: "Ashvin Durve (CC)"))
    def @controller.target_record_vrp_for_visibility(_record); @visibility_vrp; end
    assert @controller.send(:target_record_visible?, record)
    @controller.instance_variable_set(:@visibility_vrp, Vrp.new(cluster_incharge: "Ashwin Durve"))
    assert_not @controller.send(:target_record_visible?, record)
    @controller.instance_variable_set(:@visibility_vrp, Vrp.new(cluster_incharge: "Other CC"))
    assert_not @controller.send(:target_record_visible?, record)
    @controller.instance_variable_set(:@visibility_vrp, nil)
    assert_not @controller.send(:target_record_visible?, record)
  end

  test "assigned approver sees training outside their CC mapping" do
    record = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July" })
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
      "record_id" => record.id, "approvers" => ["ashvin (agricultural specialist)"], "status" => "Pending"
    })
    assert @controller.send(:target_record_visible?, record)
  end

  test "FCOC sees their office JJ but not another office" do
    def @controller.module_cluster_incharge_login?; false; end
    def @controller.current_app_user; { "username" => "fcoc", "fcoc" => "Sausar" }; end
    def @controller.target_record_vrp_for_visibility(_record); @visibility_vrp; end
    record = ModuleRecord.new(module_slug: "training-form", data: { "month" => "July" })
    @controller.instance_variable_set(:@visibility_vrp, Vrp.new(fcoc: "Sausar"))
    assert @controller.send(:target_record_visible?, record)
    @controller.instance_variable_set(:@visibility_vrp, Vrp.new(fcoc: "Other"))
    assert_not @controller.send(:target_record_visible?, record)
  end

  test "pending and returned edits do not count and untouched training still counts" do
    record = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July" })
    untouched = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July" })
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => record.id, "status" => "Returned" })
    assert_not @controller.send(:training_record_countable?, record)
    assert @controller.send(:training_record_countable?, untouched)
  end

  test "training edit resolves trainer from the saved Jeevika Jankar target" do
    vrp = Vrp.create!(name: "Correct JJ", father_husband_name: "Father", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "Bank",
      branch: "Branch", ifsc_code: "TEST0123456", address: "Address", mobile_no: "9876543012",
      email: "trainer_#{SecureRandom.hex(3)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1],
      village_ids: [1], is_active: true, is_deleted: false, user_name: "jj_#{SecureRandom.hex(3)}", password: "secret")
    target = TargetMapping.create!(vrp: vrp, fco_id: "1", fco_name: "FCO",
      ics_id: "1", ics_name: "ICS", village_id: "1", village_name: "Village",
      month_name: "October", main_activity_name: "Training",
      activity_name: "FFS", target_quantity: 1, afl_ids: [])
    record = ModuleRecord.create!(module_slug: "training-form", data: {
      "target_mapping_id" => target.id.to_s, "trainer_name" => "Admin", "trainer_contact" => "8109417150"
    })

    identity = @controller.send(:training_record_trainer_identity, record)

    assert_equal "Correct JJ", identity[:name]
    assert_equal "9876543012", identity[:contact]
    assert_equal "Correct JJ", @controller.send(:module_record_field_value, record, "Trainer Name")
    assert_equal "9876543012", @controller.send(:module_record_field_value, record, "Trainer Contact")
  end
end
