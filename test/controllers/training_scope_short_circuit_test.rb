require "test_helper"
require "open3"

class TrainingScopeShortCircuitTest < ActiveSupport::TestCase
  test "predicate reordering matches original outcomes across scope and reference combinations" do
    source, status = Open3.capture2("git", "show", "HEAD:app/controllers/modules_controller.rb")
    assert status.success?
    original = Class.new(ModulesController)
    %w[training_record_matches_dashboard_target? training_record_target_fields_match?].each do |name|
      start = source.index("  def #{name}(")
      finish = source.index("\n  def ", start + 1)
      original.class_eval(source[start...finish])
    end
    owner = Vrp.new(id: 51001, name: "JJ Name", user_name: "jj-login", mobile_no: "9000000001")
    target = TargetMapping.new(id: 52001, vrp: owner, month_name: "November", ics_id: "I", ics_name: "ICS",
      village_id: "V", village_name: "Village", main_activity_name: "Training", activity_name: "Soil")
    other_assignment = TargetMapping.new(id: 99999, vrp: owner, month_name: "November", ics_id: "Other ICS",
      village_id: "Other Village", main_activity_name: "Other Activity", activity_name: "Other Work")
    combinations = ["November", "October", ""].product(["51001", "different", nil], ["Village", "Other", nil], [nil, target.id.to_s, "99999"])
    combinations.each_with_index do |(month, owner_id, village, reference), i|
      record = ModuleRecord.new(id: 53000 + i, module_slug: "training-form", data: {
        "month" => month, "jeevika_jankar_id" => owner_id, "gram_name" => village, "ics_block" => "ICS",
        "target_mapping_id" => reference, "main_activity" => "Training", "sub_activity" => "Soil", "selected_farmer_ids" => ["1"]
      })
      controllers = [original.new, ModulesController.new]
      controllers.each do |c|
        c.define_singleton_method(:training_target_mapping_for_dashboard) { |id| id.to_s == "99999" ? other_assignment : nil }
      end
      expected = controllers.first.send(:training_record_matches_dashboard_target?, record, target, [])
      assert_equal expected, controllers.last.send(:training_record_matches_dashboard_target?, record, target, []), [month, owner_id, village, reference].inspect
      assert_equal controllers.first.send(:training_record_target_fields_match?, record, target),
        controllers.last.send(:training_record_target_fields_match?, record, target)
    end
  end

  test "scope mismatch skips unrelated assignment lookups" do
    owner = Vrp.new(id: 1, name: "JJ")
    target = TargetMapping.new(id: 2, vrp: owner, month_name: "November", village_name: "Village")
    controller = ModulesController.new
    controller.define_singleton_method(:training_record_target_assignment_matches?) { |*| raise "Unused assignment lookup" }
    record = ModuleRecord.new(id: 3, module_slug: "training-form", data: {
      "month" => "October", "target_mapping_id" => "unrelated", "selected_farmer_ids" => ["1"]
    })
    refute controller.send(:training_record_matches_dashboard_target?, record, target, [])
  end
end
