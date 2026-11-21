# Isolated rollback-only audit: no production access or external HTTP.
require "open3"
abort "Use isolated test DB" unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?("jj_performance_test_")

def measure_latest
  allocations = GC.stat(:total_allocated_objects)
  objects = 0
  observer = ->(*args) { objects += args.last[:record_count] }
  GC.start
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nil
  ActiveSupport::Notifications.subscribed(observer, "instantiation.active_record") { result = yield }
  [{ ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2),
     allocations: GC.stat(:total_allocated_objects) - allocations, instantiated: objects }, result]
end

report = { note: "Local synthetic preparation stages; rollback-only; not production full-page latency", cases: {} }
rows = 15_000.times.map { |i| { "id" => i, "module_slug" => "village-master", "data" => { "village_name" => "Village #{i}", "state_name" => "State" }.to_json } }
old_cache = ActiveSupport::Cache::MemoryStore.new(size: 64.megabytes)
new_cache = ImmutableCatalogueStore.new(size: 64.megabytes)
old_cache.write("rows", rows)
new_cache.write("rows", rows)
raise "Snapshot values changed" unless old_cache.read("rows") == new_cache.read("rows")
before, = measure_latest { 10.times { old_cache.read("rows").first(15) } }
after, = measure_latest { 10.times { new_cache.read("rows").first(15) } }
report[:cases][:ten_warm_15000_row_snapshots] = { before: before, after: after, output_equal: true,
  old_charged_bytes: old_cache.instance_variable_get(:@cache_size), new_charged_bytes: new_cache.instance_variable_get(:@cache_size) }

source, status = Open3.capture2("git", "show", "HEAD:app/controllers/vrps_controller.rb")
raise "Missing baseline" unless status.success?
a = source.index("  def vrp_detail_location_records(")
z = source.index("\n  def ", a + 1)
legacy = Class.new(VrpsController)
legacy.class_eval(source[a...z])
ActiveRecord::Base.transaction do
  now = Time.current
  15_000.times.each_slice(500) do |batch|
    ModuleRecord.insert_all!(batch.map { |i| { module_slug: "village-master", data: {
      "village_name" => "Audit Village #{i}", "state_name" => "Audit State", "district_name" => "Audit District",
      "block_name" => "Audit Block", "unused_import" => "x" * 2048
    }, created_at: now - i, updated_at: now } })
  end
  selected = ModuleRecord.where(module_slug: "village-master").order(:id).limit(2).pluck(:id)
  vrp = Vrp.new(village_ids: selected.map(&:to_s), gram_panchayat_ids: [])
  cache = ImmutableCatalogueStore.new(size: 64.megabytes)
  make_controller = lambda do
    VrpsController.new.tap do |c|
      c.define_singleton_method(:vrp_location_catalogue_cache) { cache }
      c.define_singleton_method(:shared_form_catalogue_cache) { nil }
    end
  end
  make_controller.call.send(:vrp_detail_village_index)
  before, expected = measure_latest { legacy.new.send(:vrp_detail_location_records, vrp).map(&:attributes) }
  after, actual = measure_latest { make_controller.call.send(:vrp_detail_location_records, vrp).map(&:attributes) }
  raise "Selected detail values/order changed" unless expected == actual
  report[:cases][:two_selected_villages_from_15000] = { before: before, after: after, output_equal: true }
  raise ActiveRecord::Rollback
end
module_source, status = Open3.capture2("git", "show", "HEAD:app/controllers/modules_controller.rb")
raise "Missing matching baseline" unless status.success?
legacy_matcher = Class.new(ModulesController)
%w[training_record_matches_dashboard_target? training_record_target_fields_match?].each do |name|
  start = module_source.index("  def #{name}(")
  finish = module_source.index("\n  def ", start + 1)
  legacy_matcher.class_eval(module_source[start...finish])
end
owner = Vrp.new(id: 101, name: "Owner", user_name: "owner", mobile_no: "9000000001")
target = TargetMapping.new(id: 102, vrp: owner, month_name: "November", ics_name: "ICS", village_name: "Village", main_activity_name: "Training", activity_name: "Soil")
reference = TargetMapping.new(id: 103, vrp: owner, month_name: "October", ics_name: "Other", village_name: "Other")
records = 6_000.times.map do |i|
  ModuleRecord.new(id: 100000 + i, module_slug: "training-form", data: {
    "month" => "November", "jeevika_jankar_id" => "different-owner", "target_mapping_id" => "103",
    "ics_block" => "ICS", "gram_name" => "Village", "main_activity" => "Training", "sub_activity" => "Soil", "selected_farmer_ids" => ["1"]
  })
end
controllers = [legacy_matcher.new, ModulesController.new]
controllers.each { |c| c.define_singleton_method(:training_target_mapping_for_dashboard) { |_| reference } }
before, expected = measure_latest { records.map { |r| controllers.first.send(:training_record_matches_dashboard_target?, r, target, []) } }
after, actual = measure_latest { records.map { |r| controllers.last.send(:training_record_matches_dashboard_target?, r, target, []) } }
raise "Scope results changed" unless expected == actual && actual.none?
report[:cases][:six_thousand_unrelated_training_checks] = { before: before, after: after, output_equal: true }
puts JSON.pretty_generate(report)
