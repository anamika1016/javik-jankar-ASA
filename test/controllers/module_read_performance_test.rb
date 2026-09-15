require "test_helper"

class ModuleReadPerformanceTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    @controller.instance_variable_set(:@slug, "state-master")
  end

  test "projected dropdowns preserve ordered values, JSON types, aliases and active filters" do
    payloads = [
      { "sample" => "First", "sample_name" => ["A", "B"], "sample_code" => 0 },
      { "sample" => false, "sample_title" => { "label" => "Nested" } },
      { "sample" => "First", "sample_name" => "  ", "sample_code" => true },
      { "sample" => "Inactive", "status" => "Inactive" },
      { "sample" => "Deleted", "deleted" => " YES " },
      { "unrelated" => "large payload" * 1000 },
      { "sample" => nil, "sample_code" => [], "sample_title" => {} },
      { "sample" => "Active", "status" => " ACTIVE " }
    ]
    payloads.each_with_index do |data, index|
      ModuleRecord.create!(module_slug: "performance-source", data: data, created_at: index.minutes.ago)
    end
    ModuleRecord.create!(module_slug: "state-master", data: { "sample" => "Excluded own module" })
    scope = @controller.send(:active_module_records_scope_for_all_modules).where.not(module_slug: "state-master")
    keys = %w[sample sample_name sample_title sample_code]
    expected = scope.order(created_at: :desc).flat_map { |record| keys.filter_map { |key| record.data[key].presence } }.uniq
    instantiated = 0
    subscriber = ->(*args) { instantiated += args.last[:record_count] }
    actual = nil
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      actual = @controller.send(:generic_field_options, "Sample")
    end
    assert_equal expected, actual
    assert_equal 0, instantiated, "Dropdown values should not instantiate full records"
    assert_equal expected, @controller.send(:generic_field_options, "Sample")
  end

  test "module sourced options preserve fallback key order" do
    ModuleRecord.create!(module_slug: "add-vrp-activity", data: { "sub_activity_name" => "Sub", "activity_name" => "Activity", "vrp_activity_name" => "Legacy" })
    assert_equal ["Sub", "Activity", "Legacy"], @controller.send(:values_from_module, "add-vrp-activity", "sub_activity_name")
  end

  test "ordinary static options never load the JJ dropdown" do
    @controller.define_singleton_method(:vrp_name_options) { raise "Unexpected JJ loading" }
    assert_equal Date::MONTHNAMES.compact, @controller.send(:static_field_options, "Month Name")
    assert_equal [], @controller.send(:static_field_options, "State Name")
    assert_equal ["High", "Medium", "Low"], @controller.send(:static_field_options, "Priority")
  end

  test "directory compaction matches existing prefix rules including Unicode and missing levels" do
    random = Random.new(42)
    levels = %i[state district sub_district block gram_panchayat village]
    rows = 400.times.map do |index|
      levels.to_h { |key| [key, [nil, "", " ", "A", "a ", "B", "Ä", "ä", "ग्राम"].sample(random: random)] }.merge(record_id: index)
    end
    rows.concat([{ state: "State" }, { state: "state ", village: "Village" }, {}, { state: "Unique" }])
    expected = rows.reject { |row| @controller.send(:lg_directory_prefix_covered?, row, rows) }
    assert_equal expected, @controller.send(:compact_lg_directory_rows, rows)
  end

  test "dashboard batches FCO counts while preserving aliases, distinct JJ and month matching" do
    vrp = Vrp.new(name: "Performance JJ")
    vrp.assign_attributes(aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "performance@example.test",
      experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
      mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    [["1004", "Sausar", "August"], ["1004", "Sausar", " AUGUST "],
     ["1006", "Turekela", "August"], ["Other", "Other", "August"],
     ["Other", "Other", "September"]].each do |fco_id, fco_name, month|
      TargetMapping.create!(vrp: vrp, fco_id: fco_id, fco_name: fco_name, ics_id: "ICS",
        village_id: "Village", month_name: month, main_activity_name: "Training", activity_name: "Topic", target_quantity: 1)
    end
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] if args.last[:sql].include?("COUNT(DISTINCT t.vrp_id)") }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      @controller.send(:preload_dashboard_fco_active_vrp_counts, ["Sausar", "Turekela", "Other", "Absent"], "August")
      assert_equal 1, @controller.send(:dashboard_fco_active_vrp_count, "1004", "August")
      assert_equal 1, @controller.send(:dashboard_fco_active_vrp_count, "1006", "August")
      assert_equal 1, @controller.send(:dashboard_fco_active_vrp_count, "Other", "August")
      assert_equal 0, @controller.send(:dashboard_fco_active_vrp_count, "Absent", "August")
    end
    assert_equal 1, queries.size
  end

  test "API achievements reuse records without changing duplicate farmers or other achievement rules" do
    controller = Api::V1::JeevikaJankarDashboardController.new
    targets = [101, 102].map { |id| TargetMapping.new(id: id) }
    targets.each do |target|
      ModuleRecord.create!(module_slug: "training-form", data: { "target_mapping_id" => target.id, "selected_farmer_ids" => ["1", "1", "2"] })
      ModuleRecord.create!(module_slug: "training-form", data: { "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => ["2"] })
      ModuleRecord.create!(module_slug: "seed-distribution-target", data: { "target_mapping_id" => target.id, "achievement" => "3" })
      ModuleRecord.create!(module_slug: "papl360-target", data: { "target_mapping_id" => target.id, "achievement" => "100", "status" => "Inactive" })
    end
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] if args.last[:sql].start_with?("SELECT") && args.last[:sql].include?('"module_records"') }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      2.times { targets.each { |target| assert_equal 5, controller.send(:target_achievement, target) } }
    end
    assert_equal 1, queries.size
  end
end
