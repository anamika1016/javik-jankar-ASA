# Synthetic CPU benchmark only; no DB writes. Run with RAILS_ENV=test rails runner.
abort "Use test environment" unless Rails.env.test?
require "open3"
source, status = Open3.capture2("git", "show", "HEAD:app/controllers/modules_controller.rb")
raise "Cannot load baseline" unless status.success?
baseline = Class.new(ModulesController)
method = source[/^  def approved_other_target_achievement_index\n.*?(?=^  def )/m]
baseline.class_eval(method)
owner_type = Struct.new(:name, :user_name)
target_type = Struct.new(:id, :vrp_id, :vrp, :month_name, :ics_id, :ics_name, :village_id, :village_name, :main_activity_name, :activity_name)
targets = 100.times.map { |i| target_type.new(i + 1, i + 1, owner_type.new("Person #{i}", "login#{i}"), "October", "I", "ICS", "V", "Village", "Other", "Work") }
records = 3_000.times.map do |i|
  target = targets[i % targets.size]
  data = { "target_mapping_id" => target.id.to_s, "jeevika_jankar_id" => target.vrp_id.to_s,
    "month" => "October", "ics" => "I", "village" => "V", "training_topic" => "Other",
    "training_subject" => "Work", "achievement" => (i % 5).to_s,
    "achievement_date" => "2026-10-10", "approval_status" => i % 7 == 0 ? "Pending" : "Approved" }
  # Legacy direct references without metadata and owner-name fallback rows.
  data.except!("jeevika_jankar_id", "month", "ics") if i % 11 == 0
  if i % 13 == 0
    data["target_mapping_id"] = "missing"
    data["jeevika_jankar_id"] = target.vrp.name
  end
  ModuleRecord.new(id: i + 1, module_slug: "other-target", updated_at: Time.utc(2026, 10, 10), data: data)
end
results = []
metrics = [baseline, ModulesController].map do |type|
  c = type.new
  c.define_singleton_method(:model_ready?) { |_| true }
  c.define_singleton_method(:other_target_records_for_calculation) { |_| records }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  allocated = GC.stat(:total_allocated_objects)
  results << targets.map do |target|
    c.instance_variable_set(:@other_target_candidate_targets, [target])
    c.instance_variable_set(:@other_target_candidate_targets_by_id, { target.id.to_s => target })
    c.send(:approved_other_target_achievement_index)
  end
  { ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
    allocations: GC.stat(:total_allocated_objects) - allocated }
end
raise "Achievement output changed" unless results[0] == results[1]
puts JSON.pretty_generate(note: "CPU-only synthetic scoped bill calculations; not HTTP latency", owners: targets.size,
  monthly_records: records.size, before: metrics[0], after: metrics[1], outputs_equal: true)
