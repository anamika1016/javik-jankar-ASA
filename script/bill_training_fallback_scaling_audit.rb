# CPU-only fallback benchmark with output parity; no database writes.
# Run with RAILS_ENV=test and an isolated test DATABASE_URL.
abort "Use test environment" unless Rails.env.test?
require "open3"
source, status = Open3.capture2("git", "show", "HEAD:app/controllers/modules_controller.rb")
raise "Cannot load baseline" unless status.success?
baseline = Class.new(ModulesController)
start = source.index("  def jeevika_jankar_live_training_achievement(")
finish = source.index("\n  def ", start + 1)
baseline.class_eval(source[start...finish])
owners = 100.times.map { |i| Vrp.new(id: i + 1, name: "Person #{i}", user_name: "login#{i}", mobile_no: "900000#{i}") }
targets = owners.to_h do |owner|
  [owner.id.to_s, TargetMapping.new(id: owner.id, vrp: owner, month_name: "October",
    main_activity_name: "Training", activity_name: "Work", ics_id: "I", village_id: "V")]
end
records = 3_000.times.map do |i|
  ModuleRecord.new(id: i + 1, data: { "jeevika_jankar_id" => owners[i % owners.size].id.to_s,
    "month" => "October", "main_activity" => "Training", "sub_activity" => "Work",
    "selected_farmer_ids" => [i.to_s], "ics_block" => "I", "gram_name" => "V" })
end
results = []
metrics = [baseline, ModulesController].map do |type|
  c = type.new
  c.define_singleton_method(:cached_vrp_lookup) { |id| owners[id.to_i - 1] }
  c.define_singleton_method(:jeevika_jankar_bill_target_records) { |selected_vrp_ids:, **_| selected_vrp_ids.filter_map { |id| targets[id] } }
  c.define_singleton_method(:jeevika_jankar_main_activity_settings) { {} }
  c.define_singleton_method(:jeevika_jankar_sub_activity_settings) { |_| {} }
  c.define_singleton_method(:jeevika_jankar_activity_setting_for) { |*| { main_activity_type: "Training" } }
  c.define_singleton_method(:dashboard_training_form_records_for_month) { |_| records }
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  results << owners.map do |owner|
    c.send(:jeevika_jankar_live_training_achievement,
      ModuleRecord.new(data: { "select_vrp" => owner.id.to_s, "bill_month" => "October" }))
  end
  { ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
    allocations: GC.stat(:total_allocated_objects) - allocated }
end
raise "Live training achievement changed" unless results[0] == results[1] && results[1] == Array.new(owners.size, 30.0)
puts JSON.pretty_generate(note: "Synthetic fallback CPU benchmark, not full page/production latency", owners: owners.size,
  monthly_training_records: records.size, before: metrics[0], after: metrics[1], outputs_equal: true)
