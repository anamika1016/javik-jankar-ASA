require "test_helper"

class ModuleLookupPerformanceTest < ActiveSupport::TestCase
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

  private

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
end
