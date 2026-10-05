require "test_helper"

class RequestLookupScalingTest < ActiveSupport::TestCase
  test "approver matching does not reload current user for each VRP" do
    user = User.create!(first_name: "Scaling", last_name: "Approver", user_name: "scaling_approver",
      email: "scaling_approver@example.test", password: "secret", role: "Manager", status: "Active")
    legacy = ModuleRecord.new(module_slug: "new-user", data: { "user_name" => user.user_name, "first_name" => "Legacy", "last_name" => "Approver" })
    legacy.save!(validate: false)
    controller = VrpsController.new
    controller.instance_variable_set(:@current_app_user, { "id" => user.id, "username" => user.user_name, "name" => user.full_name, "role" => user.role })
    queries = capture_queries do
      100.times do
        assert controller.send(:approver_matches_current_user?, "Scaling Approver (Manager)")
        assert controller.send(:approver_matches_current_user?, "Legacy Approver")
        assert_not controller.send(:approver_matches_current_user?, "Unrelated Person")
      end
    end
    assert_equal 2, queries.size
  end

  test "hierarchy traversal preserves newest match multi-level chains cycles and inactive rows" do
    create_mapping("Old Head", ["Coordinator"], created_at: 2.days.ago)
    create_mapping("Team Lead", ["Coordinator (CC)", "Another CC"], created_at: 1.day.ago)
    create_mapping("Field Agronomist", ["Team Lead"], created_at: 1.hour.ago)
    create_mapping("Wrong Agronomist", ["Coordinator"], status: "Inactive")
    create_mapping("Cycle B", ["Cycle A"])
    create_mapping("Cycle A", ["Cycle B"])
    controller = ModulesController.new
    queries = capture_queries do
      3.times do
        assert_equal "Field Agronomist", controller.send(:user_hierarchy_head_for_cc, "Coordinator (CC)")
        assert_equal "Cycle B", controller.send(:user_hierarchy_head_for_cc, "Cycle A")
        assert_nil controller.send(:user_hierarchy_head_for_cc, "Unknown")
        map = controller.send(:user_hierarchy_cc_to_head_map)
        assert_equal "Field Agronomist", map["another cc"]
        assert_equal "Cycle A", map["cycle b"]
      end
    end
    assert_equal 1, queries.size
  end

  test "display field keys preserve aliases numeric values arrays blanks and primary priority" do
    controller = ModulesController.new
    record = ModuleRecord.new(module_slug: "block-master", data: {
      "block_name" => "Primary", "block" => "Alias", "cd_block_code" => 12,
      "completion_date" => "", "date" => "2026-10-05", "main_activity" => ["A", "B"] })
    3.times do
      assert_equal "Primary", controller.send(:module_record_field_value, record, "Block Name")
      assert_equal 12, controller.send(:module_record_field_value, record, "Block Code")
      assert_equal "2026-10-05", controller.send(:module_record_field_value, record, "Completion Date")
      assert_equal ["A", "B"], controller.send(:module_record_field_value, record, "Main Activity")
      assert_nil controller.send(:module_record_field_value, record, "Missing")
    end
  end

  test "bill target loading uses one query and preserves numeric-month fallback" do
    vrp = Vrp.new(name: "Target Query JJ", aadhar_no: "123456789012", account_no: "123",
      address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "target-query@example.test", experience_in_years: 0, father_husband_name: "Test",
      gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    target = TargetMapping.new(vrp_id: vrp.id, fco_id: "F1", ics_id: "I1", village_id: "V1",
      month_name: "October", activity_name: "Soil", main_activity_name: "Training", target_quantity: 1)
    target.save!(validate: false)
    ["October", "10"].each do |month|
      controller = ModulesController.new
      controller.instance_variable_set(:@current_app_user, { "user_type" => "admin" })
      controller.define_singleton_method(:jeevika_jankar_bill_selected_vrp_ids) { |_| [vrp.id.to_s] }
      controller.define_singleton_method(:vrp_dashboard_target_progress_rows) { |*_| [] }
      controller.define_singleton_method(:jeevika_jankar_main_activity_settings) { {} }
      controller.define_singleton_method(:jeevika_jankar_sub_activity_settings) { |_| {} }
      controller.define_singleton_method(:approved_other_target_achievement_index) { {} }
      queries = []
      callback = ->(*args) do
        payload = args.last
        queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].match?(/SELECT.*FROM "target_mappings"/m)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        controller.send(:jeevika_jankar_bill_rows, vrp_id: vrp.id.to_s, month_name: month, totals_only: true)
      end
      assert_equal [target.id], controller.instance_variable_get(:@other_target_candidate_targets).map(&:id)
      assert_equal 1, queries.size if month == "October"
    end
  end

  private

  def create_mapping(head, members, created_at: Time.current, status: "Active")
    ModuleRecord.create!(module_slug: "user-hierarchy-mapping", created_at: created_at,
      data: { "level_1_user" => head, "level_2_users" => members, "status" => status })
  end

  def capture_queries
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].match?(/SELECT.*FROM "(?:users|module_records)"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
