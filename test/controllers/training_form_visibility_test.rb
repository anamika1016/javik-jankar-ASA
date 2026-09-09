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
end
