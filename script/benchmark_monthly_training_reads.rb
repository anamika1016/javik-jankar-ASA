# Rollback-only test benchmark for blocked training/photo payload reads.
require "json"
require "open3"
raise "Use RAILS_ENV=test" unless Rails.env.test?
raise "Use an isolated DB" unless ActiveRecord::Base.connection.current_database.start_with?("jj_feature_removal_test_", "jj_performance_test_")
ref = ENV.fetch("PERFORMANCE_BASELINE_REF", "7dbf517")
source, status = Open3.capture2("git", "show", "#{ref}:app/controllers/modules_controller.rb")
raise "Cannot load baseline" unless status.success?
a = source.index("  def dashboard_training_form_records_by_month(month)")
b = source.index("\n  def ", a + 1)
baseline = Class.new(ModulesController)
baseline.class_eval(source[a...b])
revision_source, status = Open3.capture2("git", "show", "#{ref}:app/services/training_edit_approval.rb")
raise "Cannot load baseline revision reader" unless status.success?
a = revision_source.index("  def self.unapproved_record_ids")
b = revision_source.index("\n  def ", a + 1)
legacy_revisions = Class.new(TrainingEditApproval)
legacy_revisions.class_eval(revision_source[a...b])
baseline.define_method(:training_record_countable?) do |record|
  @unapproved_training_record_ids ||= legacy_revisions.unapproved_record_ids.to_set
  !@unapproved_training_record_ids.include?(record.id.to_s) && training_record_status_countable?(record)
end

def monthly_metrics
  count = 0
  instantiated = 0
  sql = ->(*args) { count += 1 if args.last[:name] != "SCHEMA" && !args.last[:cached] && args.last[:sql].start_with?("SELECT") }
  objects = ->(*args) { instantiated += args.last[:record_count] }
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  gc_time = GC.stat(:time)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rows = nil
  ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
    ActiveSupport::Notifications.subscribed(objects, "instantiation.active_record") { rows = yield }
  end
  [{ milliseconds: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2), queries: count,
     instantiated: instantiated, allocations: GC.stat(:total_allocated_objects) - allocated, gc_ms: GC.stat(:time) - gc_time }, rows]
end

report = { baseline_ref: ref, note: "200 photo-heavy entries; 180 have a pending latest revision; fixtures roll back" }
ActiveRecord::Base.transaction do
  200.times do |index|
    row = ModuleRecord.create!(module_slug: "training-form", created_at: index.minutes.ago,
      data: { "month" => "October", "photo_front_view" => ["image-#{index}-" + "x" * 64000], "selected_farmer_ids" => [index.to_s] })
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => row.id.to_s, "status" => "Pending", "before" => { "evidence" => "y" * 5000 } }) if index < 180
  end
  results = []
  [baseline, ModulesController].each_with_index do |klass, index|
    ActiveRecord::Base.uncached { klass.new.send(:dashboard_training_form_records_by_month, "october") }
    metrics, rows = ActiveRecord::Base.uncached { monthly_metrics { klass.new.send(:dashboard_training_form_records_by_month, "october") } }
    report[index.zero? ? :before : :after] = metrics.merge(returned_rows: rows.size)
    results << rows.map(&:attributes)
  end
  raise "Payload/order changed" unless results[0] == results[1]
  scope = ModulesController.new.send(:active_module_records_scope, "training-form")
    .where("LOWER(BTRIM(data::jsonb ->> 'month')) = 'october'")
  plan = ActiveRecord::Base.connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{ModuleRecordReadQuery.without_unapproved_training_records(scope, TrainingEditApproval.unapproved_record_ids).to_sql}")
  parsed = plan.is_a?(String) ? JSON.parse(plan) : plan
  find_indexes = lambda do |node|
    [node["Index Name"], *Array(node["Plans"]).flat_map { |child| find_indexes.call(child) }].compact
  end
  report[:indexes_in_actual_plan] = find_indexes.call(parsed.first["Plan"]).uniq
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
