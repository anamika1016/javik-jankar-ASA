require "test_helper"

class LogHotspotPerformanceTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "missing payment owners are batch checked once and retain saved fallback totals" do
    controller = calculator
    calls = []
    controller.define_singleton_method(:jeevika_jankar_bill_rows) do |**options|
      calls << options
      @jeevika_jankar_target_summary = {}
      []
    end
    bills = 30.times.map do |index|
      ModuleRecord.new(data: { "select_vrp" => (index + 1).to_s, "bill_month" => "October",
        "total_target" => "77", "total_achievement" => "22" })
    end
    controller.send(:preload_jeevika_bill_process_totals, bills)
    2.times do
      assert_equal Array.new(30, ["77", "22"]), bills.map { |bill|
        [controller.send(:jeevika_jankar_bill_total_target, bill), controller.send(:jeevika_jankar_bill_total_achievement, bill)]
      }
      controller.send(:preload_jeevika_bill_process_totals, bills)
    end
    assert_equal 1, calls.size
  end

  test "batched missing canonical numeric and mixed owners match individual calculation" do
    bills = 8.times.map do |index|
      vrp = build_vrp(index)
      months = case index % 4
      when 0 then ["October", "10"]
      when 1 then ["10"]
      when 2 then ["November"]
      else []
      end
      months.each do |month|
        TargetMapping.create!(vrp: vrp, fco_id: "F", ics_id: "I", village_id: "V",
          month_name: month, main_activity_name: "Other", activity_name: "Work", target_quantity: index + 1)
      end
      ModuleRecord.new(data: { "select_vrp" => vrp.id.to_s, "bill_month" => "October",
        "total_target" => "88", "total_achievement" => "33" })
    end
    individual = calculator
    expected = bills.map { |bill| totals(individual, bill) }
    batched = calculator
    batched.send(:preload_jeevika_bill_process_totals, bills)
    assert_equal expected, bills.map { |bill| totals(batched, bill) }
    queries = capture_queries { bills.each { |bill| totals(batched, bill) } }
    assert_empty queries
  end

  test "training target headers preserve scope saved exceptions and database ordering" do
    owner = build_vrp(20)
    targets = ["Train", "Other", "Unknown", "Alias", "Train"].each_with_index.map do |activity, index|
      TargetMapping.create!(vrp: owner, fco_id: "F", ics_id: "I", village_id: "V",
        ics_name: index.even? ? "B" : "A", month_name: "October", main_activity_name: activity,
        activity_name: "Work", target_quantity: 1, afl_ids: Array.new(100) { |n| "#{index}-#{n}" })
    end
    settings = { "train" => { main_activity_type: "Training" }, "other" => { main_activity_type: "Other" } }
    subs = { "alias" => settings["train"] }
    saved = targets[1].id
    controller = calculator
    predicate = lambda do |target|
      setting = controller.send(:jeevika_jankar_activity_setting_for, target, settings, subs)
      target.id == saved || (setting.present? && controller.send(:training_main_activity_type?, setting[:main_activity_type]))
    end
    scope = TargetMapping.where(id: targets.first(4).map(&:id)).order(:ics_name, :id)
    expected = scope.to_a.select(&predicate)
    result = nil
    queries = capture_queries { result = TargetFormReadQuery.filter(scope, &predicate).to_a }
    assert_equal expected.map(&:attributes), result.map(&:attributes)
    refute_includes queries.first, '"afl_ids"'
    assert_includes queries.first, '"main_activity_name"'
    assert_equal 2, queries.size
  end

  test "observation candidate filtering preserves ratings and skips unrelated bill payloads" do
    controller = calculator
    controller.params = ActionController::Parameters.new(bill_month: "October")
    controller.define_singleton_method(:preload_bill_list_identities!) { |_| }
    controller.define_singleton_method(:jeevika_jankar_bill_record_visible?) { |_| true }
    payloads = [nil, {}, [], "text", { "work" => "good" }, { "work" => false }, { "work" => [] }, { "work" => "  " }]
    bills = payloads.map do |observations|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
        "select_vrp_name" => "JJ", "bill_month" => "October", "observations" => observations,
        "bill_items" => [{ "farmer_details" => [{ "name" => "x" * 5000 }] }]
      })
    end
    expected = bills.select { |bill| controller.send(:jeevika_bill_observation_row, bill).present? }.map(&:id).sort
    queries = capture_queries { controller.send(:prepare_jeevika_jankar_observation_list) }
    assert_equal expected, controller.instance_variable_get(:@observation_rows).map { |row| row[:id] }.sort
    assert queries.any? { |sql| sql.include?("jsonb_typeof") && sql.include?("observations") }
    bills.each { |bill| assert bill.reload.data["bill_items"].first.key?("farmer_details") }
  end

  test "role dropdowns reuse narrow user and module catalogues without changing labels" do
    User.create!(user_name: "hotspot_user", password: "secret", first_name: "Role", last_name: "User",
      role: "Agronomist", person_type: "Cluster Coordinator")
    ModuleRecord.create!(module_slug: "new-user", data: { "user_name" => "hotspot_module",
      "first_name" => "Legacy", "role" => "Agronomist", "person_type" => "Cluster Coordinator", "private" => "x" * 10000 })
    controller = calculator
    queries = capture_queries do
      assert_includes controller.send(:registered_app_user_rows_matching, /agronomist/i), "Role User"
      assert_includes controller.send(:registered_app_user_rows_matching, /cluster/i), "Role User"
      assert_includes controller.send(:registered_module_user_rows_matching, /agronomist/i), "Legacy"
      assert_includes controller.send(:registered_module_user_rows_matching, /cluster/i), "Legacy"
    end
    assert_equal 2, queries.size
    refute queries.any? { |sql| sql.include?('"users".*') || sql.include?('"module_records".*') }
    refute controller.send(:training_staff_option_users).last.has_attribute?(:password)
    refute controller.send(:training_staff_option_module_users).first.data.key?("private")
  end

  test "location revision stays the same digest across repeated reads" do
    controller = calculator
    first = controller.send(:location_catalogue_revision)
    assert_kind_of String, first
    assert_equal first, controller.send(:location_catalogue_revision)
  end

  test "empty bill visibility does not load all approval histories" do
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: { "bill_id" => "outside" })
    controller = calculator
    controller.instance_variable_set(:@jeevika_bill_visible_record_ids, [])
    queries = capture_queries { assert_equal({}, controller.send(:jeevika_bill_approval_history_by_bill_id)) }
    assert_empty queries
  end

  test "browser location JSON preserves the payload and warm renders skip rebuilding it" do
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Quoted \"State\"", "state_code" => "02" })
    first = calculator
    expected = first.send(:location_hierarchy_mappings).to_json
    assert_equal expected, first.send(:location_hierarchy_browser_json)
    warm = calculator
    warm.define_singleton_method(:location_hierarchy_mappings) { raise "Warm form must reuse the serialized catalogue" }
    assert_equal expected, warm.send(:location_hierarchy_browser_json)
  end

  test "browser location JSON invalidates on direct edits with unchanged timestamps" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Before JSON Edit" })
    before = calculator.send(:location_hierarchy_browser_json)
    record.update_columns(data: { "state_name" => "After JSON Edit" })
    after = calculator.send(:location_hierarchy_browser_json)
    refute_equal before, after
    assert_includes after, "After JSON Edit"
    refute_includes after, "Before JSON Edit"
  end

  test "training reference preload does not materialize the global dashboard target scope" do
    owner = build_vrp(40)
    target = TargetMapping.create!(vrp: owner, fco_id: "F", ics_id: "I", village_id: "V",
      month_name: "October", main_activity_name: "Training", activity_name: "Work", target_quantity: 1)
    record = ModuleRecord.new(data: { "target_mapping_ids" => [target.id.to_s, "99999999"] })
    controller = calculator
    controller.define_singleton_method(:dashboard_target_mappings) { raise "Global dashboard load is unrelated to these references" }
    queries = capture_queries do
      controller.send(:preload_training_target_mappings_for_records!, [record])
      3.times do
        assert_equal target.id, controller.send(:training_target_mapping_for_dashboard, target.id).id
        assert_nil controller.send(:training_target_mapping_for_dashboard, "99999999")
      end
    end
    target_queries = queries.select { |sql| sql.include?('FROM "target_mappings"') }
    assert_equal 1, target_queries.size
    assert_includes target_queries.first, 'WHERE'
    assert_equal owner.name, controller.send(:training_target_mapping_for_dashboard, target.id).vrp.name
  end

  test "training reference lookup reuses an already loaded dashboard target" do
    target = TargetMapping.new(id: 12345)
    controller = calculator
    controller.instance_variable_set(:@dashboard_target_mappings, [target])
    queries = capture_queries do
      assert_same target, controller.send(:training_target_mapping_for_dashboard, target.id)
    end
    assert_empty queries
  end

  test "projected legacy staff names preserve nested JSON values and their key order" do
    payloads = [
      { "role" => "Agronomist", "first_name" => { "z" => "Last", "a" => "First" }, "last_name" => ["L", "N"] },
      { "role" => ["Agronomist"], "first_name" => false, "last_name" => "", "user_name" => "fallback" },
      { "role" => "Agronomist", "first_name" => "Normal", "last_name" => "Name", "extra" => "unused" }
    ]
    records = payloads.each_with_index.map do |data, index|
      ModuleRecord.create!(module_slug: "new-user", data: data, updated_at: index.minutes.ago)
    end
    expected = records.filter_map do |record|
      [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence || record.data["user_name"].presence
    end
    assert_equal expected, calculator.send(:registered_module_user_rows_matching, /agronomist/i)
  end

  test "bill totals reuse already loaded targets when resolving training references" do
    owner = build_vrp(55)
    farmer = Afl.create!(farmer_name: "Reuse Farmer", fco_id: "F")
    target = TargetMapping.create!(vrp: owner, fco_id: "F", ics_id: "I", village_id: "V",
      month_name: "October", main_activity_name: "Training", activity_name: "Work", target_quantity: 1, afl_ids: [farmer.id])
    ModuleRecord.create!(module_slug: "add-activity-group", data: { "main_activity_name" => "Training", "main_activity_type" => "Training" })
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "jeevika_jankar_id" => owner.id.to_s,
      "target_mapping_id" => target.id.to_s, "main_activity" => "Training", "sub_activity" => "Work",
      "selected_farmer_ids" => [farmer.id.to_s], "training_date" => "2026-10-10" })
    controller = calculator
    controller.send(:jeevika_jankar_bill_rows, vrp_id: owner.id.to_s, month_name: "October", totals_only: true)
    queries = capture_queries do
      controller.send(:preload_training_target_mappings_for_records!, ModuleRecord.where(module_slug: "training-form").to_a)
      assert_equal target.id, controller.send(:training_target_mapping_for_dashboard, target.id).id
    end
    refute queries.any? { |sql| sql.include?('FROM "target_mappings"') }
  end

  test "approval history uses requested bill rather than unrelated form record context" do
    history = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history",
      data: { "bill_id" => "112233", "action" => "Approved" })
    controller = calculator
    controller.instance_variable_set(:@record, ModuleRecord.new(id: 778899, module_slug: "other-target", data: { "month" => "October" }))
    bill = ModuleRecord.new(id: 112233, module_slug: "jeevika-jankar-bill-process", data: { "month" => "October" })
    assert_equal [history.id], controller.send(:jeevika_bill_approval_history, bill).map(&:id)
  end

  private

  def calculator
    controller = ModulesController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new
    controller.define_singleton_method(:current_app_user) { { "user_type" => "admin", "record_type" => "User" } }
    controller
  end

  def totals(controller, bill)
    [controller.send(:jeevika_jankar_bill_total_target, bill), controller.send(:jeevika_jankar_bill_total_achievement, bill)]
  end

  def build_vrp(index)
    vrp = Vrp.new(name: "Hotspot JJ #{index}", aadhar_no: "123456789012", account_no: "123", address: "Test",
      branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "hotspot#{index}@example.test",
      experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
      mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    vrp
  end

  def capture_queries
    queries = []
    subscriber = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && !payload[:cached] && payload[:sql].start_with?("SELECT")
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
