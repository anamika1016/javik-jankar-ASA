require "test_helper"

class ApiVrpReadScalingTest < ActiveSupport::TestCase
  class Reader
    include VrpAccess
    private
    def current_app_user
      { "user_type" => "admin", "record_type" => "User" }
    end
  end

  test "list payloads match independent uncached reads and repeated type creator and history reads are bounded" do
    creator = User.create!(first_name: "Read Creator", user_name: "api_scaling_creator", password: "secret", status: "Active")
    type = VrpType.create!(type_name: "Read Type", is_active: true, is_deleted: false)
    rows = 30.times.map { |i| create_vrp(i, created_by_id: creator.id, created_by_type: "User", vrp_type_ids: [type.id]) }
    ModuleRecord.create!(module_slug: "vrp-approval-history", data: { "vrp_id" => rows.first.id.to_s, "action" => "Sent for Approval" })
    expected = rows.map { |row| Reader.new.send(:list_row_payload, row) }
    reader = Reader.new
    queries = []
    actual = capture_queries(queries) do
      reader.send(:preload_vrp_approval_history_lookup_data!, rows)
      rows.map { |row| reader.send(:list_row_payload, row) }
    end
    assert_equal expected, actual
    assert_equal 1, queries.count { |sql| sql.include?("vrp-approval-history") }
    assert_equal 1, queries.count { |sql| sql.include?('FROM "vrp_types"') }
    assert_equal 1, queries.count { |sql| sql.include?('FROM "users"') && sql.include?('"users"."id" =') }
  end

  test "batch approval histories preserve legacy numeric coercion and chronology" do
    vrp = create_vrp(100)
    history = ["000#{vrp.id}", "#{vrp.id}legacy", vrp.id].map do |value|
      ModuleRecord.create!(module_slug: "vrp-approval-history", data: { "vrp_id" => value, "action" => "Sent for Approval" })
    end
    reader = Reader.new
    expected = reader.send(:approval_history_for, vrp).map(&:id)
    batch = Reader.new
    batch.send(:preload_vrp_approval_history_lookup_data!, [vrp])
    assert_equal history.map(&:id), expected
    assert_equal expected, batch.send(:approval_history_for, vrp).map(&:id)
  end

  test "approval-related JJ visibility batches history reads without changing matching rows" do
    rows = 12.times.map { |index| create_vrp(200 + index, status: 10) }
    rows.each do |vrp|
      ModuleRecord.create!(module_slug: "vrp-approval-history", data: {
        "vrp_id" => "000#{vrp.id}", "action" => "Sent for Approval", "action_by" => "Batch Approver"
      })
    end

    reader = Reader.new
    reader.define_singleton_method(:approver_labels) { ["Batch Approver"] }
    queries = []
    visible = capture_queries(queries) { reader.send(:approval_related_vrps) }

    assert_equal rows.map(&:id).sort, visible.map(&:id).sort
    assert_equal 1, queries.count { |sql| sql.include?("vrp-approval-history") }
  end

  test "training village reads are reused without changing mapped IDs or missing farmer fallbacks" do
    farmer = Afl.create!(farmer_name: "Village Read", village_id: "performance-village")
    vrp = create_vrp(101)
    targets = 20.times.map do |i|
      TargetMapping.create!(vrp: vrp, fco_id: "fco", ics_id: "ics", village_id: "performance-village",
        month_name: "October", main_activity_name: "Training", activity_name: "Activity #{i}",
        target_quantity: 1, afl_ids: ["legacy-#{i}"])
    end
    controller = ModulesController.new
    controller.define_singleton_method(:village_external_farmer_ids) { |*| ["external-farmer"] }
    queries = []
    values = capture_queries(queries) { targets.map { |target| controller.send(:target_live_farmer_ids, target) } }
    targets.each_with_index do |target, i|
      assert_equal ["legacy-#{i}", farmer.id.to_s, "external-farmer"], values[i]
      assert_equal values[i], controller.send(:target_live_farmer_ids, target)
    end
    assert_equal 1, queries.count { |sql| sql.include?('FROM "afls"') }
  end

  test "other target farmer preload batches distinct villages and preserves target farmer order" do
    first = Afl.create!(farmer_name: "First Village", village_id: "village-one")
    second = Afl.create!(farmer_name: "Second Village", village_id: "village-two")
    vrp = create_vrp(102)
    targets = [
      TargetMapping.create!(vrp: vrp, fco_id: "fco", ics_id: "ics", village_id: "village-one", month_name: "October",
        main_activity_name: "Other", activity_name: "Activity One", target_quantity: 1, afl_ids: ["mapped-one"]),
      TargetMapping.create!(vrp: vrp, fco_id: "fco", ics_id: "ics", village_id: "village-two", month_name: "October",
        main_activity_name: "Other", activity_name: "Activity Two", target_quantity: 1, afl_ids: ["mapped-two"])
    ]
    controller = ModulesController.new
    controller.define_singleton_method(:preload_village_external_farmer_details!) { |_ids| {} }
    controller.define_singleton_method(:village_external_farmer_ids) do |ids|
      ids.map { |id| "external-#{id}" }
    end

    queries = []
    capture_queries(queries) { controller.send(:preload_live_target_farmers!, targets) }

    assert_equal ["mapped-one", first.id.to_s, "external-village-one"], controller.send(:target_live_farmer_ids, targets.first)
    assert_equal ["mapped-two", second.id.to_s, "external-village-two"], controller.send(:target_live_farmer_ids, targets.second)
    assert_equal 1, queries.count { |sql| sql.include?('FROM "afls"') }
  end

  test "other target compact browser payload expands to the original mappings" do
    shared = { id: "farmer-1", farmer_name: "Shared Farmer" }
    unique = { id: "farmer-2", farmer_name: "Unique Farmer" }
    mappings = [
      { target_mapping_id: "1", farmers: [shared, unique] },
      { target_mapping_id: "2", farmers: [shared] }
    ]
    controller = ModulesController.new
    controller.define_singleton_method(:seed_distribution_target_mappings) { mappings }

    payload = controller.send(:seed_distribution_target_browser_payload)
    expanded = payload[:mappings].map do |mapping|
      mapping.except(:farmer_indexes).merge(farmers: mapping[:farmer_indexes].map { |index| payload[:farmers][index] })
    end

    assert_equal mappings, expanded
    assert_equal [shared, unique], payload[:farmers]
  end

  test "other with farmer initial payload keeps target metadata and defers live farmer rows" do
    mapping = { target_mapping_id: "1", village: "Village", farmers: [{ id: "farmer-1" }], mapped_farmer_ids: ["farmer-1"] }
    controller = ModulesController.new
    controller.define_singleton_method(:record_source_slug) { "other-target-with-farmer" }
    controller.define_singleton_method(:seed_distribution_target_mappings) { [mapping] }

    payload = controller.send(:seed_distribution_target_browser_payload)

    assert_equal [], payload[:farmers]
    assert_equal [mapping.except(:farmers)], payload[:mappings]
  end

  test "other with farmer form setup defers the live village query until target selection" do
    vrp = Struct.new(:name, :user_name, :mobile_no).new("JJ One", "jj-one", "9876543210")
    target = Struct.new(:id, :vrp_id, :vrp, :month_name, :ics_name, :ics_id, :village_name, :village_id,
      :main_activity_name, :activity_name, :target_quantity, :afl_ids).new(
        1, 1, vrp, "October", "ICS One", "ics-1", "Village One", "village-1",
        "Other Activity", "Subject", 10, ["mapped-farmer"]
      )
    relation = Object.new
    relation.define_singleton_method(:includes) { |*| self }
    relation.define_singleton_method(:order) { |*| self }
    relation.define_singleton_method(:to_a) { [target] }

    controller = ModulesController.new
    controller.define_singleton_method(:model_ready?) { |_| true }
    controller.define_singleton_method(:record_source_slug) { "other-target-with-farmer" }
    controller.define_singleton_method(:training_target_scope) { relation }
    controller.define_singleton_method(:jeevika_jankar_main_activity_settings) { [] }
    controller.define_singleton_method(:jeevika_jankar_sub_activity_settings) { |_| [] }
    controller.define_singleton_method(:jeevika_jankar_activity_setting_for) { |*| { main_activity_type: "Other with Farmer" } }
    controller.define_singleton_method(:other_with_farmer_target_exhausted?) { |_| false }
    controller.define_singleton_method(:preload_other_target_completed_farmer_ids!) { |_| nil }
    controller.define_singleton_method(:preload_training_farmers_for_targets!) { |_| raise "initial form must not preload farmers" }
    controller.define_singleton_method(:preload_live_target_farmers!) { |_| raise "initial form must not query live villages" }
    controller.define_singleton_method(:target_live_farmer_ids) { |_| raise "initial form must not resolve live farmers" }
    controller.define_singleton_method(:target_farmer_ids) { |_| ["mapped-farmer"] }
    controller.define_singleton_method(:other_target_completed_farmer_ids_for) { |_| ["done-farmer"] }
    controller.define_singleton_method(:registered_vrp_fcoc) { |_| "FCO One" }
    controller.define_singleton_method(:new_farmer_target_mapping?) { |_| false }

    mapping = controller.send(:build_seed_distribution_target_mappings).sole

    assert_equal [], mapping[:farmers]
    assert_equal ["mapped-farmer"], mapping[:mapped_farmer_ids]
    assert_equal ["done-farmer"], mapping[:completed_farmer_ids]
  end

  test "external village details are fetched once as a grouped batch" do
    controller = ModulesController.new
    calls = []
    controller.define_singleton_method(:fetch_training_external_farmer_names) do |ids, needed = nil, group_by_village: false|
      calls << [ids, needed, group_by_village]
      ids.to_h { |id| [id, { "farmer-#{id}" => { farmer_name: "Farmer #{id}" } }] }
    end

    controller.send(:preload_village_external_farmer_details!, %w[village-one village-two])

    assert_equal [[%w[village-one village-two], nil, true]], calls
    assert_equal ["farmer-village-one"], controller.send(:village_external_farmer_ids, ["village-one"])
    assert_equal ["farmer-village-two"], controller.send(:village_external_farmer_ids, ["village-two"])
  end

  private

  def capture_queries(queries, &block)
    callback = ->(*args) do
      payload = args.last
      if payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT")
        queries << ([payload[:sql]] + Array(payload[:binds]).map(&:value_for_database)).join(" ")
      end
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
  end

  def create_vrp(index, **attributes)
    vrp = Vrp.new({ name: "API Read #{index}", fcoc: "FCO-Test", aadhar_no: "123456789012",
      account_no: "123", address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current, email: "api-read-#{index}@example.test", experience_in_years: 0,
      father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210",
      office_detail_id: 0, to_office_detail_id: 0, status: 10 }.merge(attributes))
    vrp.save!(validate: false)
    vrp
  end
end
