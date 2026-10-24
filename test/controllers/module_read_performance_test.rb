require "test_helper"

class ModuleReadPerformanceTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    @controller.instance_variable_set(:@slug, "state-master")
  end

  test "other achievement indexes reuse empty results and follow candidate scope changes" do
    first = TargetMapping.new(id: 91001, month_name: "September")
    second = TargetMapping.new(id: 91002, month_name: "October")
    ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => second.id.to_s, "month" => "October", "achievement" => "3"
    })
    queries = []
    subscriber = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.start_with?("SELECT") && sql.include?('"module_records"."module_slug" IN')
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      @controller.instance_variable_set(:@other_target_candidate_targets, [first])
      3.times { assert_equal({}, @controller.send(:approved_other_target_achievement_index)) }
      @controller.instance_variable_set(:@other_target_candidate_targets, [second])
      @controller.instance_variable_set(:@other_target_candidate_targets_by_id, { second.id.to_s => second })
      3.times { assert_equal 3.0, @controller.send(:approved_other_target_achievement_index).dig(second.id.to_s, :achievement) }
      @controller.instance_variable_set(:@other_target_candidate_targets, [first])
      assert_equal({}, @controller.send(:approved_other_target_achievement_index))
    end
    assert_equal 2, queries.size
  end

  test "other target contact numbers are batch loaded with mapping precedence and legacy fallbacks" do
    mapped_vrp = performance_vrp("111-222-3333")
    legacy_vrp = performance_vrp("444-555-6666")
    mapping = TargetMapping.create!(vrp: mapped_vrp, fco_id: "FCO", fco_name: "FCO", ics_id: "ICS",
      village_id: "Village", month_name: "October", main_activity_name: "Training", activity_name: "Topic", target_quantity: 1)
    mapped_record = ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => "mapping-#{mapping.id}", "vrp_id" => legacy_vrp.id, "Contact Number" => "saved value"
    })
    legacy_record = ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => "missing", "jeevika_jankar_id" => legacy_vrp.id, "Contact Number" => "saved value"
    })
    fallback_record = ModuleRecord.create!(module_slug: "other-target", data: { "Contact Number" => "saved value" })
    @controller.instance_variable_set(:@slug, "other-target-list")
    @controller.define_singleton_method(:target_record_visible?) { |_record| true }

    queries = []
    subscriber = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.start_with?("SELECT") && (sql.include?('"target_mappings"') || sql.include?('"vrps"'))
    end
    records = nil
    contacts = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      records = @controller.send(:module_records)
      contacts = [mapped_record, legacy_record, fallback_record].map do |record|
        @controller.send(:module_record_field_value, record, "Contact Number")
      end
    end

    assert_equal [mapped_record.id, legacy_record.id, fallback_record.id].sort, records.map(&:id).sort
    assert_equal ["1112223333", "4445556666", "saved value"], contacts
    assert_equal 2, queries.size
  end

  test "new training form defers mapped farmer lookups to the existing selected-target endpoint" do
    target = Struct.new(:id, :afl_ids, :vrp_id, :vrp, :month_name, :ics_name, :ics_id, :village_name,
      :village_id, :main_activity_name, :activity_name).new(
        77, ["farmer-1", "farmer-2"], 12, Struct.new(:name, :user_name, :mobile_no).new("JJ", "jj", "9876543210"),
        "October", "ICS", "ics-1", "Village", "village-1", "Training", "Soil"
      )
    relation = Object.new
    relation.define_singleton_method(:or) { |_| self }
    relation.define_singleton_method(:includes) { |*| self }
    relation.define_singleton_method(:order) { |*| self }
    relation.define_singleton_method(:to_a) { [target] }

    controller = ModulesController.new
    controller.instance_variable_set(:@slug, "training-form")
    controller.define_singleton_method(:action_name) { "show" }
    controller.define_singleton_method(:model_ready?) { |_| true }
    controller.define_singleton_method(:training_target_scope) { relation }
    controller.define_singleton_method(:jeevika_jankar_main_activity_settings) { { "training" => { main_activity_type: "Training" } } }
    controller.define_singleton_method(:jeevika_jankar_sub_activity_settings) { |_| {} }
    controller.define_singleton_method(:jeevika_jankar_activity_setting_for) { |*| { main_activity_type: "Training" } }
    controller.define_singleton_method(:target_farmer_ids) { |row| row.afl_ids }
    controller.define_singleton_method(:new_farmer_target_mapping?) { |_| false }
    controller.define_singleton_method(:training_farmers_for_ids) { |_| raise "new form should fetch farmers on selection" }

    mapping = controller.send(:build_training_target_mappings).sole

    assert_equal ["farmer-1", "farmer-2"], mapping[:farmer_ids]
    assert_equal [], mapping[:farmers]
    assert controller.send(:training_form_initial_render?)

    controller.define_singleton_method(:action_name) { "dashboard" }
    controller.define_singleton_method(:training_farmers_for_ids) do |ids|
      ids.map { |id| { id: id, farmer_name: "Loaded #{id}" } }
    end
    dashboard_mapping = controller.send(:build_training_target_mappings).sole
    assert_equal ["farmer-1", "farmer-2"], dashboard_mapping[:farmers].map { |farmer| farmer[:id] }
    assert_not controller.send(:training_form_initial_render?)
  end

  test "training activity settings share the same ordered setup records" do
    record = ModuleRecord.new(data: {
      "main_activity" => "Training", "sub_activity_name" => "Soil health",
      "main_activity_type" => "Training", "activity_type" => "Workshop"
    })
    relation = Object.new
    loads = 0
    relation.define_singleton_method(:order) { |**_| self }
    relation.define_singleton_method(:to_a) { loads += 1; [record] }
    @controller.define_singleton_method(:model_ready?) { |_| true }
    @controller.define_singleton_method(:active_module_records_scope) { |slug| raise unless slug == "add-vrp-activity"; relation }

    assert_equal({ "training" => ["Soil health"] }, @controller.send(:training_setup_sub_activities_by_main))
    activity_settings = { "training" => { main_activity_type: "Training" } }
    assert_equal({ "soil health" => { main_activity_type: "Training" } },
      @controller.send(:jeevika_jankar_sub_activity_settings, activity_settings))
    assert_equal 1, loads
  end

  test "registered app user options retain labels and newest-first order with projected columns" do
    older = User.create!(user_name: "staff_old_#{SecureRandom.hex(4)}", password: "secret",
      first_name: "Older", last_name: "Staff", stakeholder: "PAPL")
    newer = User.create!(user_name: "staff_new_#{SecureRandom.hex(4)}", password: "secret",
      first_name: "Newer", last_name: "Staff", stakeholder: "PAPL")
    older.update_column(:updated_at, 2.days.ago)
    newer.update_column(:updated_at, 1.day.ago)

    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] if args.last[:sql].include?('FROM "users"') }
    names = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      names = @controller.send(:registered_app_user_names)
    end

    assert_operator names.index("Newer Staff"), :<, names.index("Older Staff")
    assert_equal 1, queries.size
    assert_match(/SELECT\s+"users"\."first_name",\s*"users"\."last_name",\s*"users"\."user_name"/i, queries.first)
  end

  def performance_vrp(mobile_no)
    vrp = Vrp.new(name: "Performance JJ")
    vrp.assign_attributes(aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "#{mobile_no}@example.test",
      experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
      mobile_no: mobile_no, office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    vrp
  end

  test "training list batches trainer identities with identical target and fallback precedence" do
    @controller.define_singleton_method(:vrp_login_user?) { false }
    first_vrp = performance_vrp("9000000001")
    second_vrp = performance_vrp("9000000002")
    fallback_vrp = performance_vrp("9000000003")
    first_target = TargetMapping.create!(vrp: first_vrp, fco_id: "FCO", ics_id: "ICS", village_id: "Village",
      month_name: "October", main_activity_name: "Training", activity_name: "First", target_quantity: 1)
    second_target = TargetMapping.create!(vrp: second_vrp, fco_id: "FCO", ics_id: "ICS", village_id: "Village",
      month_name: "October", main_activity_name: "Training", activity_name: "Second", target_quantity: 1)
    records = [
      ModuleRecord.create!(module_slug: "training-form", data: {
        "target_mapping_ids" => [second_target.id.to_s, first_target.id.to_s], "trainer_name" => "Stale"
      }),
      ModuleRecord.create!(module_slug: "training-form", data: {
        "target_mapping_id" => "missing", "jeevika_jankar_id" => fallback_vrp.id.to_s, "trainer_name" => "Stale"
      }),
      ModuleRecord.create!(module_slug: "training-form", data: {
        "trainer_name" => "Saved trainer", "trainer_contact" => "Saved contact"
      })
    ]
    queries = []
    subscriber = lambda do |*args|
      sql = args.last[:sql].to_s
      queries << sql if sql.start_with?("SELECT") && (sql.include?('"target_mappings"') || sql.include?('"vrps"'))
    end

    identities = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      3.times { @controller.send(:preload_training_record_trainer_identities!, records) }
      identities = 3.times.map { records.map { |record| @controller.send(:training_record_trainer_identity, record) } }
    end

    expected = [
      { name: first_vrp.name, contact: first_vrp.mobile_no },
      { name: fallback_vrp.name, contact: fallback_vrp.mobile_no },
      { name: "Saved trainer", contact: "Saved contact" }
    ]
    identities.each { |result| assert_equal expected, result }
    assert_equal 3, queries.size
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

  test "training form edit does not load the separate training form list" do
    @controller.instance_variable_set(:@slug, "training-form")
    @controller.instance_variable_set(:@record, ModuleRecord.new(module_slug: "training-form"))

    assert_not @controller.send(:module_records_required_for_show?)
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

  test "LG directory reads all source modules once while preserving rows and newest-first order" do
    older = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Older State" }, created_at: 2.days.ago)
    newer = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Newer State" }, created_at: 1.day.ago)
    village = ModuleRecord.create!(module_slug: "village-master", data: {
      "state" => "Newer State", "district" => "District", "block" => "Block",
      "gram_panchayat" => "GP", "village_name" => "Village", "status" => "Inactive"
    })
    queries = []
    subscriber = lambda do |*args|
      sql = args.last[:sql].to_s
      queries << sql if sql.start_with?("SELECT") && sql.include?('"module_records"')
    end

    state_rows = nil
    all_rows = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      3.times do
        state_rows = @controller.send(:lg_rows_from_records, "state-master", state: "state_name")
        all_rows = @controller.send(:lg_directory_rows)
      end
    end

    assert_operator state_rows.index { |row| row[:record_id] == newer.id }, :<,
      state_rows.index { |row| row[:record_id] == older.id }
    assert_includes all_rows.map { |row| row[:record_id] }, village.id
    assert_equal "Inactive", all_rows.find { |row| row[:record_id] == village.id }[:status]
    # The directory checks one compact source revision so cached results remain
    # fresh across requests; all source payloads are still read only once.
    assert_equal 2, queries.size
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

  test "API dashboard batches fallback VRP mappings while preserving mapped farmer ids" do
    controller = Api::V1::JeevikaJankarDashboardController.new
    vrps = [201, 202].map do |id|
      Vrp.new(id: id).tap { |vrp| vrp.save!(validate: false) }
    end
    targets = vrps.map.with_index do |vrp, index|
      TargetMapping.new(vrp_id: vrp.id, fco_id: "FCO#{index}", ics_id: "ICS#{index}",
        village_id: "Village#{index}", afl_ids: [])
    end
    vrps.each_with_index do |vrp, index|
      VrpIcsMapping.create!(vrp_id: vrp.id, fco_id: "FCO#{index}", ics_id: "ICS#{index}",
        village_id: "Village#{index}", afl_ids: [index + 10, index + 20])
    end

    queries = []
    subscriber = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:sql].include?('"vrp_ics_mappings"')
    end
    results = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      controller.send(:preload_dashboard_mappings, targets)
      results = targets.map { |target| controller.send(:mapped_farmer_ids, target) }
    end

    assert_equal [["10", "20"], ["11", "21"]], results
    assert_equal 1, queries.size
  end
end
