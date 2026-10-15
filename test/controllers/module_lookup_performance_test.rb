require "test_helper"

class ModuleLookupPerformanceTest < ActiveSupport::TestCase
  test "target lookup keeps admin and VRP scopes from intersecting the cluster scope" do
    own_vrp = create_test_vrp("Own Other Target")
    cluster_vrp = create_test_vrp("Cluster Other Target")
    own_target = create_lookup_target(own_vrp)
    create_lookup_target(cluster_vrp)

    vrp_controller = ModulesController.new
    vrp_controller.define_singleton_method(:current_slug) { "other-target" }
    vrp_controller.define_singleton_method(:vrp_login_user?) { true }
    vrp_controller.define_singleton_method(:current_vrp_record) { own_vrp }
    vrp_controller.define_singleton_method(:admin_dashboard_user?) { false }
    vrp_controller.define_singleton_method(:module_mapped_vrp_scope_active?) { true }
    vrp_controller.define_singleton_method(:module_cluster_visible_vrp_ids) { [cluster_vrp.id] }

    assert_equal [own_target.id], vrp_controller.send(:training_target_scope).pluck(:id)

    admin_controller = ModulesController.new
    admin_controller.define_singleton_method(:current_slug) { "other-target" }
    admin_controller.define_singleton_method(:vrp_login_user?) { false }
    admin_controller.define_singleton_method(:admin_dashboard_user?) { true }
    admin_controller.define_singleton_method(:module_mapped_vrp_scope_active?) { true }
    admin_controller.define_singleton_method(:module_cluster_visible_vrp_ids) { [cluster_vrp.id] }

    assert_equal [own_target.id, TargetMapping.where(vrp: cluster_vrp).pick(:id)].sort,
      admin_controller.send(:training_target_scope).pluck(:id).sort
  end

  test "Other Target edit keeps saved ICS available when its target mapping is no longer active" do
    controller = ModulesController.new
    record = ModuleRecord.new(data: { "ics" => "Saved September ICS" })
    controller.instance_variable_set(:@record, record)
    controller.define_singleton_method(:seed_distribution_target_mappings) { [] }

    assert_equal ["Saved September ICS"], controller.send(:seed_distribution_target_field_options, "ICS")
  end

  test "cluster visibility matches fuzzy labels after reading only distinct cluster labels" do
    cluster_label = "Lookup#{SecureRandom.hex(4)} Person"
    matching = create_test_vrp("#{cluster_label} (Cluster Incharge)")
    create_test_vrp("Other#{SecureRandom.hex(4)} Person (Cluster Incharge)")
    controller = ModulesController.new
    controller.define_singleton_method(:model_ready?) { |_| true }
    controller.define_singleton_method(:current_cluster_incharge_labels) { [cluster_label] }
    controller.define_singleton_method(:module_cluster_incharge_login?) { false }
    controller.define_singleton_method(:jeevika_jankar_transferred_vrps) { [] }

    queries = []
    subscriber = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.include?(%Q{FROM "vrps"})
    end
    visible = nil
    directly_mapped_ids = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      visible = controller.send(:module_cluster_visible_vrps)
      directly_mapped_ids = controller.send(:module_directly_mapped_cluster_vrp_ids)
    end

    assert_equal [matching.id], visible.map(&:id)
    assert_equal [matching.id], directly_mapped_ids
    assert_equal 3, queries.size
    assert_match(/DISTINCT.*cluster_incharge/m, queries.first)
    assert_match(/WHERE.*cluster_incharge/m, queries.last)
  end

  test "dashboard office visibility preserves normalized FCO and TO matches" do
    office = "Performance#{SecureRandom.hex(4)}"
    matching_fcoc = create_test_vrp("FCO Match", fcoc: "FCO-C #{office}")
    matching_to = create_test_vrp("TO Match", to_name: office)
    outside = create_test_vrp("Outside", fcoc: "Elsewhere#{SecureRandom.hex(4)}", to_name: "Other")
    controller = ModulesController.new
    controller.define_singleton_method(:model_ready?) { |_| true }
    controller.define_singleton_method(:current_app_user) { { "office_name" => office } }

    queries = []
    callback = ->(*args) { queries << args.last[:sql] if args.last[:sql].include?(%Q{FROM "vrps"}) }
    visible = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      visible = controller.send(:dashboard_office_visible_vrps)
    end

    assert_equal [matching_fcoc.id, matching_to.id].sort, visible.map(&:id).sort
    assert_not_includes visible.map(&:id), outside.id
    assert_equal 3, queries.size
    assert queries[0].include?("DISTINCT")
    assert queries[1].include?("DISTINCT")
    assert_match(/WHERE/, queries.last)
  end

  test "dashboard approval visibility only loads VRPs referenced by approval history" do
    recorded = create_test_vrp("Approval Candidate")
    create_test_vrp("No Approval History")
    ModuleRecord.create!(module_slug: "vrp-approval-history", data: {
      "vrp_id" => recorded.id.to_s, "action" => "Sent for Approval"
    })
    controller = ModulesController.new
    controller.define_singleton_method(:model_ready?) { |_| true }
    controller.define_singleton_method(:preload_dashboard_vrp_identity_records!) { |_| nil }
    controller.define_singleton_method(:vrp_approval_sent?) { |_| true }
    controller.define_singleton_method(:dashboard_current_user_in_approval_channel?) { |_| true }

    vrp_queries = []
    callback = ->(*args) do
      sql = args.last[:sql]
      vrp_queries << sql if sql.include?(%Q{FROM "vrps"})
    end
    visible = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      visible = controller.send(:dashboard_approval_related_vrps)
    end

    assert_equal [recorded.id], visible.map(&:id)
    assert_equal 1, vrp_queries.size
    assert_match(/WHERE.*id/m, vrp_queries.first)
  end

  test "lightweight location rows preserve flags order and JSON value types" do
    records = [
      { "state" => "S", "district" => "D", "block_name" => "First", "status" => " Active " },
      { "block_name" => "Inactive", "status" => "Inactive" },
      { "block_name" => "Deleted", "deleted" => " YES " },
      { "block_name" => "Last", "block_code" => 123, "aliases" => ["a", "b"] }
    ].each_with_index.map do |data, index|
      ModuleRecord.create!(module_slug: "block-master", data: data, created_at: index.minutes.ago)
    end
    controller = ModulesController.new
    expected = ModuleRecord.where(module_slug: "block-master").order(created_at: :desc)
      .select { |record| controller.send(:active_module_record?, record) }
      .map { |record| [record.id, record.data] }

    queries = capture_queries("module_records") do
      2.times do
        actual = controller.send(:active_records_for_location, "block-master")
        assert_equal expected, actual.map { |record| [record.id, record.data] }
      end
    end
    assert_equal 1, queries.size
    assert_equal records.first.id, expected.first.first
  end

  test "location index preserves first matching candidate aliases and ignores numeric names" do
    controller = ModulesController.new
    candidates = [
      { "state_name" => " S ", "district_name" => "D", "cd_block_name" => "B", "gp_code" => "12", "gram_name" => "First" },
      { "state" => "S", "district" => "D", "block" => "B", "gram_code" => "12", "gram_name" => "Second" },
      { "state" => "S", "district" => "D", "block" => "Other", "gp_code" => "12", "gram_name" => "Other" },
      { "state" => "S", "district" => "D", "block" => "B", "gp_code" => "13" }
    ].map { |data| ModuleRecord.new(data: data) }
    controller.define_singleton_method(:gram_panchayat_location_records) { candidates }
    village = ModuleRecord.new(data: { "state" => "S", "district" => "D", "block" => "B" })
    assert_equal "First", controller.send(:gram_panchayat_name_by_location, village, "12")
    assert_nil controller.send(:gram_panchayat_name_by_location, village, "13")
    assert_nil controller.send(:gram_panchayat_name_by_location, village, "missing")
  end

  test "VRP label index preserves ID priority and first match across competing labels" do
    controller = ModulesController.new
    first = Vrp.new(id: 901, name: "Alias", user_name: "first", mobile_no: "9876500001")
    second = Vrp.new(id: 902, name: "Second", user_name: "Alias", mobile_no: "9876500002")
    third = Vrp.new(id: 903, name: "alias", user_name: "third")
    vrps = [first, second, third]
    controller.define_singleton_method(:cached_vrps_by_id) { vrps.index_by { |vrp| vrp.id.to_s } }
    ["Alias", " ALIAS ", "first", "9876500002", "902", "missing"].each do |label|
      expected = vrps.find { |vrp| vrp.id.to_s == label } || vrps.find do |vrp|
        vrp.name.to_s == label || vrp.user_name.to_s == label || vrp.mobile_no.to_s == label ||
          vrp.name.to_s.downcase == controller.send(:normalize_dashboard_text, label).downcase
      end
      actual = controller.send(:cached_vrp_lookup, label)
      expected ? assert_equal(expected.id, actual&.id) : assert_nil(actual)
    end
  end

  test "approval channel lookup queries once for multiple rows and retains inactive steps" do
    data = { "module_name" => "VRP Bill", "stakeholder_name" => "Staff", "user_name" => "Person" }
    first = ModuleRecord.create!(module_slug: "approval-master", data: data.merge("status" => "Inactive"), created_at: 2.minutes.ago)
    second = ModuleRecord.create!(module_slug: "approval-master", data: data.merge("approval_level" => "Second Approval"))
    controller = ModulesController.new
    queries = capture_queries("module_records") do
      [first, second].each do |record|
        assert_equal [first.id, second.id], controller.send(:approval_channel_records_for, record).map(&:id)
      end
    end
    assert_equal 1, queries.size
  end

  test "approver dropdown reuses users across approval form rows" do
    User.create!(first_name: "Lookup", last_name: "Approver", user_name: "lookup_approver",
      email: "lookup-approver@example.test", mobile_no: "9876500098", password: "secret",
      role: "Manager", status: "Active")
    controller = ModulesController.new
    expected = User.order(created_at: :desc).filter_map do |user|
      name = user.full_name.presence || user.user_name.presence
      next if name.blank?

      user.role.present? ? "#{name} (#{user.role})" : name
    end.uniq
    queries = capture_queries("users") do
      3.times { assert_equal expected, controller.send(:approver_options) }
    end
    assert_equal 1, queries.size
  end

  test "training mapping payload is built once across all dependent dropdowns" do
    controller = ModulesController.new
    calls = 0
    payload = [{ target_mapping_id: "1", farmer_ids: ["a"], farmers: [{ id: "a", farmer_name: "Saved" }] }]
    controller.define_singleton_method(:build_training_target_mappings) { calls += 1; payload }
    4.times { assert_equal payload, controller.send(:training_target_mappings) }
    assert_equal 1, calls
  end

  test "bill totals omit unused farmer display data and preserve target summary" do
    controller = ModulesController.new
    vrp = Vrp.new(id: 9001, name: "Summary JJ")
    target = TargetMapping.new(id: 9002, vrp: vrp, month_name: "August", target_quantity: 10)
    relation = Object.new
    relation.define_singleton_method(:where) { |*_| self }
    relation.define_singleton_method(:none?) { false }
    relation.define_singleton_method(:order) { |*_| self }
    relation.define_singleton_method(:load) { self }
    relation.define_singleton_method(:loaded?) { true }
    relation.define_singleton_method(:to_a) { [target] }
    progress = { target_record: target, target_mapping_id: "9002", month: "August", target: 10,
      completed: 4, pending: 6, assigned_farmer_ids: [], completed_farmer_ids: [] }
    controller.define_singleton_method(:vrp_login_user?) { false }
    controller.define_singleton_method(:module_mapped_vrp_scope_active?) { false }
    controller.define_singleton_method(:jeevika_jankar_main_activity_settings) { {} }
    controller.define_singleton_method(:jeevika_jankar_sub_activity_settings) { |_| {} }
    controller.define_singleton_method(:jeevika_jankar_activity_setting_for) { |*_| { main_activity_type: "Other" } }
    controller.define_singleton_method(:approved_other_target_achievement_index) { {} }
    controller.define_singleton_method(:vrp_dashboard_target_progress_rows) { |*_| [progress] }
    controller.define_singleton_method(:jeevika_jankar_farmers_by_id) { |_| {} }
    controller.define_singleton_method(:jeevika_jankar_training_index) { |_| {} }
    original_includes = TargetMapping.method(:includes)
    TargetMapping.define_singleton_method(:includes) { |*_| relation }
    begin
      full = controller.send(:jeevika_jankar_bill_rows, vrp_id: "9001", month_name: "August")
      expected = controller.send(:jeevika_jankar_target_summary_from_rows, full)
      controller.define_singleton_method(:jeevika_jankar_farmers_by_id) { |_| raise "unused farmer metadata" }
      controller.define_singleton_method(:jeevika_jankar_training_index) { |_| raise "unused training display index" }
      rows = controller.send(:jeevika_jankar_bill_rows, vrp_id: "9001", month_name: "August", totals_only: true)
      assert_equal expected, controller.send(:jeevika_jankar_target_summary_from_rows, rows)
      assert_equal expected, controller.instance_variable_get(:@jeevika_jankar_target_summary)
    ensure
      TargetMapping.define_singleton_method(:includes, original_includes)
    end
  end

  test "payment passbooks preload once across JJs including missing attachments" do
    vrps = 3.times.map do |index|
      vrp = Vrp.new(name: "Passbook JJ #{index}", aadhar_no: "123456789012", account_no: "123",
        address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
        email: "passbook-#{index}@example.test", experience_in_years: 0, father_husband_name: "Test",
        gender: 1, ifsc_code: "TEST0123456", mobile_no: "987654321#{index}", office_detail_id: 0, to_office_detail_id: 0)
      vrp.save!(validate: false)
      vrp
    end
    controller = ModulesController.new
    controller.define_singleton_method(:jeevika_bill_vrp) { |record| record }
    queries = capture_queries("active_storage_attachments") do
      2.times do
        controller.send(:preload_jeevika_payment_passbooks!, vrps)
        vrps.each { |vrp| assert_not vrp.bank_passbook_upload.attached? }
      end
    end
    assert_equal 1, queries.size
  end

  test "batched location catalogue preserves lookup values and projects only required data" do
    ModulesController::LOCATION_MODULE_SLUGS.each_with_index do |slug, index|
      ModuleRecord.create!(module_slug: slug, created_at: index.minutes.ago, data: {
        "state_name" => "State", "state_code" => "01", "district_name" => "District",
        "district_code" => "02", "block_name" => "Block", "cd_block_code" => "03",
        "gram_name" => "Gram", "gp_code" => "04", "village_name" => "Village",
        "village_code" => "05", "status" => " Active ", "extra" => [1, false] })
      ModuleRecord.create!(module_slug: slug, data: { "name" => "Deleted", "discarded" => " yes " })
    end
    legacy = ModulesController.new
    legacy.define_singleton_method(:preload_location_records!) { |_| }
    expected = legacy.send(:location_hierarchy_mappings)
    controller = ModulesController.new
    queries = capture_queries("module_records") do
      2.times { assert_equal expected, controller.send(:location_hierarchy_mappings) }
    end
    assert_equal 1, queries.size
    assert_includes queries.first, "jsonb_object_agg"
    assert_not_includes queries.first, "extra"
    %w[state_id district_id block_id gram_panchayat_id village_id].each do |key|
      assert_includes queries.first, key
    end
  end

  test "gram label lookup retains active aliases without instantiating full records" do
    ModuleRecord.create!(module_slug: "gram-panchayat-master", data: { "gp_code" => "991", "gram_name" => "Lookup Gram" })
    ModuleRecord.create!(module_slug: "lg-directory-list", data: { "gp_code" => "992", "gp_name" => "Directory Gram" })
    ModuleRecord.create!(module_slug: "village-master", data: { "gp_code" => "993", "gram_name" => "Deleted Gram", "is_deleted" => "TRUE" })
    controller = ModulesController.new
    instantiated = 0
    subscriber = ->(*args) { instantiated += args.last[:record_count] }
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      lookup = controller.send(:gram_panchayat_name_lookup)
      assert_equal "Lookup Gram", lookup["991"]
      assert_equal "Directory Gram", lookup["992"]
      assert_nil lookup["993"]
      assert_equal 2, controller.send(:gram_panchayat_location_records).size
    end
    assert_equal 0, instantiated
  end

  private

  def create_test_vrp(cluster_incharge = nil, **attributes)
    vrp = Vrp.new({ name: "Performance #{SecureRandom.hex(4)}", cluster_incharge: cluster_incharge,
      aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "performance-#{SecureRandom.hex(4)}@example.test", experience_in_years: 0,
      father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210",
      office_detail_id: 0, to_office_detail_id: 0 }.merge(attributes))
    vrp.save!(validate: false)
    vrp
  end

  def capture_queries(table)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].include?(%Q{"#{table}"})
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  private

  def create_lookup_target(vrp)
    TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO-#{vrp.id}",
      ics_id: "ICS-#{vrp.id}",
      ics_name: "ICS #{vrp.id}",
      village_id: "V-#{vrp.id}",
      village_name: "Village #{vrp.id}",
      month_name: "September",
      main_activity_name: "Other Activity",
      activity_name: "Other Sub Activity",
      target_quantity: 10
    )
  end
end
