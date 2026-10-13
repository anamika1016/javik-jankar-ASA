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
