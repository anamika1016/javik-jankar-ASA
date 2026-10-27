# Run with rails runner in an isolated test database. All fixtures roll back.
require "json"
require "open3"
raise "Use RAILS_ENV=test" unless Rails.env.test?
raise "Use an isolated database" unless ActiveRecord::Base.connection.current_database.start_with?("jj_feature_removal_test_", "jj_performance_test_")

baseline_ref = ENV.fetch("PERFORMANCE_BASELINE_REF", "HEAD")
source, status = Open3.capture2("git", "show", "#{baseline_ref}:app/controllers/modules_controller.rb")
raise "Cannot load baseline" unless status.success?
legacy = Class.new(ModulesController)
method_start = source.index("  def preload_jeevika_bill_process_totals(records)")
method_end = source.index("\n  def ", method_start + 1)
legacy.class_eval(source[method_start...method_end])

def measure_hotspot
  queries = 0
  rows = 0
  subscriber = ->(*args) do
    payload = args.last
    queries += 1 if payload[:name] != "SCHEMA" && !payload[:cached] && payload[:sql].start_with?("SELECT")
  end
  objects = ->(*args) { rows += args.last[:record_count] }
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nil
  ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
    ActiveSupport::Notifications.subscribed(objects, "instantiation.active_record") { result = yield }
  end
  [{ milliseconds: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
     queries: queries, instantiated: rows, allocations: GC.stat(:total_allocated_objects) - allocated }, result]
end

resolved_ref, = Open3.capture2("git", "rev-parse", baseline_ref)
report = { baseline_ref: resolved_ref.strip, database: ActiveRecord::Base.connection.current_database }
ActiveRecord::Base.transaction do
  ModuleRecord.create!(module_slug: "add-activity-group", data: { "main_activity_name" => "Training", "main_activity_type" => "Training" })
  bills = 30.times.map do |number|
    ModuleRecord.new(module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => (900_000 + number).to_s, "bill_month" => "October", "total_target" => "77", "total_achievement" => "22"
    })
  end
  [legacy, ModulesController].each_with_index do |klass, index|
    build_controller = lambda do
      controller = klass.new
      controller.request = ActionDispatch::TestRequest.create
      controller.params = ActionController::Parameters.new
      controller.define_singleton_method(:current_app_user) { { "user_type" => "admin", "record_type" => "User" } }
      controller
    end
    calculate = lambda do |controller|
      controller.send(:preload_jeevika_bill_process_totals, bills)
      bills.map { |bill| [controller.send(:jeevika_jankar_bill_total_target, bill), controller.send(:jeevika_jankar_bill_total_achievement, bill)] }
    end
    # Warm schema metadata equally, and disable SQL query caching for both runs.
    ActiveRecord::Base.uncached { calculate.call(build_controller.call) }
    controller = build_controller.call
    metrics, result = ActiveRecord::Base.uncached { measure_hotspot { calculate.call(controller) } }
    raise "Displayed totals changed" unless result == Array.new(30, ["77", "22"])
    report[index.zero? ? :before : :after] = metrics
  end
  owner = Vrp.new(name: "Header benchmark owner", aadhar_no: "123456789012", account_no: "123", address: "Test",
    branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "header-benchmark@example.test",
    experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
    mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
  owner.save!(validate: false)
  targets = 100.times.map do |number|
    TargetMapping.create!(vrp: owner, fco_id: "bench", ics_id: "I", village_id: "V", month_name: "October",
      main_activity_name: number < 10 ? "Training" : "Other", activity_name: "Work", target_quantity: 2000,
      afl_ids: Array.new(2000) { |n| "benchmark-farmer-#{number}-#{n}" })
  end
  target_ids = targets.map(&:id)
  predicate = ->(target) { target.main_activity_name == "Training" }
  relation = -> { TargetMapping.where(id: target_ids).order(:ics_name, :ics_id, :village_name, :village_id, :id) }
  before, expected = ActiveRecord::Base.uncached do
    measure_hotspot { relation.call.to_a.select(&predicate).map { |target| [target.id, target.afl_ids] } }
  end
  after, actual = ActiveRecord::Base.uncached do
    measure_hotspot { TargetFormReadQuery.filter(relation.call, &predicate).map { |target| [target.id, target.afl_ids] } }
  end
  raise "Target form payload/order changed" unless expected == actual
  report[:training_headers_100_targets_2000_ids_each] = { before: before, after: after }
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
