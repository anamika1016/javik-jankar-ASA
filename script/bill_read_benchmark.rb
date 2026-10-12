# Isolated synthetic read benchmark; all inserted records are rolled back.
# RAILS_ENV=test bin/rails runner script/bill_read_benchmark.rb
require "benchmark"
abort "Use RAILS_ENV=test with a dedicated test database" unless Rails.env.test?

def measure_bill_read
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  queries = 0
  callback = ->(*args) do
    payload = args.last
    queries += 1 if payload[:name] != "SCHEMA" && !payload[:cached] && payload[:sql].start_with?("SELECT")
  end
  value = nil
  seconds = Benchmark.realtime do
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { value = yield }
  end
  [{ milliseconds: (seconds * 1000).round(2), queries: queries,
    allocations: GC.stat(:total_allocated_objects) - allocated }, value]
end

def bill_calculator
  controller = ModulesController.new
  controller.request = ActionDispatch::TestRequest.create
  controller.params = ActionController::Parameters.new
  controller.define_singleton_method(:current_app_user) { { "user_type" => "admin", "record_type" => "User" } }
  controller
end

report = {}
ActiveRecord::Base.transaction do
  bills = 25.times.map do |index|
    vrp = Vrp.new(name: "Read Audit JJ #{index}", fcoc: "Audit FCO", aadhar_no: "123456789012", account_no: "123",
      address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "read-audit-#{index}@example.test", experience_in_years: 0, father_husband_name: "Test", gender: 1,
      ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0,
      agreement_signature_data: "s" * 65_536)
    vrp.save!(validate: false)
    TargetMapping.create!(vrp: vrp, fco_id: "audit-fco", fco_name: "Audit FCO", ics_id: "ics", village_id: "village",
      month_name: "September", main_activity_name: "Farmers' Training", activity_name: "Soil", target_quantity: 10)
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => vrp.id.to_s, "bill_month" => "September", "grand_total" => "1500.00",
      "bill_items" => [{ "activity" => "Soil", "assigned_count" => 10, "achievement_count" => 0,
        "farmer_details" => 500.times.map { |farmer| { "id" => farmer.to_s, "name" => "x" * 1024 } } }]
    })
  end
  scope = ModuleRecord.where(id: bills.map(&:id)).order(:id)
  controller = bill_calculator
  before, full = measure_bill_read { scope.to_a.each(&:data) }
  after, projected = measure_bill_read { controller.send(:bill_summary_scope, scope).to_a.each(&:data) }
  expected = full.map do |bill|
    data = bill.data.deep_dup
    data["bill_items"].each { |item| item.delete("farmer_details") }
    data
  end
  raise "Projected bill values changed" unless expected == projected.map(&:data)
  report[:bill_payload_25_bills_500_farmer_details_each] = { before: before, after: after,
    bytes_before: full.sum { |bill| bill.data.to_json.bytesize },
    bytes_after: projected.sum { |bill| bill.data.to_json.bytesize }, summary_values_equal: true }
  individual = bill_calculator
  before, expected = measure_bill_read do
    projected.map { |bill| [individual.send(:jeevika_jankar_bill_total_target, bill), individual.send(:jeevika_jankar_bill_total_achievement, bill)] }
  end
  batched = bill_calculator
  after, actual = measure_bill_read do
    batched.send(:preload_jeevika_bill_process_totals, projected)
    projected.map { |bill| [batched.send(:jeevika_jankar_bill_total_target, bill), batched.send(:jeevika_jankar_bill_total_achievement, bill)] }
  end
  raise "Batched live totals changed" unless expected == actual
  report[:live_bill_totals_25_jjs_one_month] = { before: before, after: after, totals_equal: true }
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
