require "test_helper"

class TargetMappingOptionMemoizationTest < ActiveSupport::TestCase
  test "module options retain the legacy active-status rule while reading only needed JSON keys" do
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => "Visible", "status" => "Active", "unused_upload" => "x" * 10_000
    })
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => "Legacy blank status"
    })
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => "Hidden lowercase status", "status" => "active"
    })
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => "Hidden inactive status", "status" => "Inactive"
    })

    options = TargetMappingsController.new.send(:module_options, "add-activity-group", "main_activity_name")

    assert_equal ["Legacy blank status", "Visible"], options.sort
  end

  test "target type labels reuse one activity-type lookup for the whole list" do
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => "Training Activity", "main_activity_type" => "Training", "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => "Village Activity", "main_activity_type" => "Other", "status" => "Active"
    })
    controller = TargetMappingsController.new
    training = TargetMapping.new(main_activity_name: "Training Activity")
    village = TargetMapping.new(main_activity_name: "Village Activity")
    queries = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      queries << sql if sql.match?(/SELECT.*FROM "module_records"/m)
    end

    labels = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      labels = [
        controller.send(:target_type_label_for, training),
        controller.send(:target_type_label_for, village),
        controller.send(:target_type_label_for, training)
      ]
    end

    assert_equal ["Farmer", "Villages", "Farmer"], labels
    assert_equal 1, queries.size,
      "each target row must reuse the same activity-type map rather than requerying it"
  end
end
