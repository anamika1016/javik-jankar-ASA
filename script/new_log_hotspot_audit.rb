# Rollback-only comparison for the 13 Nov production log hotspots.
# RAILS_ENV=test DATABASE_URL=<isolated test DB> bundle exec rails runner script/new_log_hotspot_audit.rb
require "open3"
require "tmpdir"
abort "Use an isolated test database" unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?("jj_performance_test_")
require "net/http"
Net::HTTP.prepend(Module.new do
  private
  def connect
    raise SocketError, "External HTTP disabled for synthetic audit"
  end
end)

def audit_source(path)
  source, status = Open3.capture2("git", "show", "HEAD:#{path}")
  raise "Cannot load baseline" unless status.success?
  source
end

def audit_method(source, name)
  start = source.index("  def #{name}(") || source.index("  def #{name}\n")
  finish = source.index("\n  def ", start + 1)
  source[start...finish]
end

def audit_measure
  sql_count = 0
  callback = ->(*args) { sql_count += 1 if args.last[:name] != "SCHEMA" && !args.last[:cached] && args.last[:sql].start_with?("SELECT") }
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nil
  ActiveRecord::Base.uncached do
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { result = yield }
  end
  [{ ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
     queries: sql_count, allocations: GC.stat(:total_allocated_objects) - allocated }, result]
end

source = audit_source("app/controllers/modules_controller.rb")
legacy = Class.new(ModulesController)
Object.class_eval(audit_source("app/services/module_field_options_cache.rb").sub("class ModuleFieldOptionsCache", "class LogAuditLegacyOptionsCache"))
legacy.class_eval(audit_method(source, "projected_module_field_values").gsub("ModuleFieldOptionsCache", "LogAuditLegacyOptionsCache"))
legacy.class_eval(audit_method(source, "module_record_sort_value"))
previous_cache = Rails.cache
shared_directory = Dir.mktmpdir("form-catalogue-audit-")
Rails.cache = ActiveSupport::Cache::MemoryStore.new(size: 128.megabytes)
report = { note: "Synthetic local measurements; external HTTP disabled; writes rolled back; not production latency" }
begin
  ActiveRecord::Base.transaction do
    now = Time.current
    20_000.times.each_slice(500) do |indexes|
      ModuleRecord.insert_all!(indexes.map { |i| { module_slug: "unrelated-log-audit", data: { "row" => i }, created_at: now, updated_at: now } })
    end
    8_000.times.each_slice(500) do |indexes|
      ModuleRecord.insert_all!(indexes.map { |i| { module_slug: "village-master", data: {
        "state_name" => "Audit State", "district_name" => "Audit District", "block_name" => "Audit Block",
        "gram_panchayat_name" => "Audit GP #{i / 10}", "village_name" => "Audit Village #{i} <&", "status" => "Active"
      }, created_at: now - i, updated_at: now } })
    end
    scopes = 4.times.map do |i|
      slug = "log-audit-options-#{i}"
      ModuleRecord.create!(module_slug: slug, data: { "first" => "One #{i}", "second" => "Two #{i}", "third" => "Three #{i}" })
      ModuleRecord.where(module_slug: slug)
    end
    option_results = []
    option_metrics = [legacy, ModulesController].map do |type|
      warm = type.new
      scopes.each { |scope| %w[first second third].each { |key| warm.send(:projected_module_field_values, scope, [key]) } }
      controller = type.new
      metrics, result = audit_measure { scopes.flat_map { |scope| %w[first second third].map { |key| controller.send(:projected_module_field_values, scope, [key]) } } }
      option_results << result
      metrics
    end
    raise "Dropdown values/order changed" unless option_results[0] == option_results[1]
    report[:warm_dropdowns_12_fields] = { before: option_metrics[0], after: option_metrics[1], outputs_equal: true }

    row_type = Struct.new(:id, :module_slug, :data)
    rows = 15_000.times.map { |i| row_type.new(i, "village-master", { "state_name" => "State #{i % 10}", "village_name" => "Village #{i}" }) }
    sort_results = []
    sort_metrics = [legacy, ModulesController].map do |type|
      c = type.new
      c.instance_variable_set(:@module, ModulesController::MODULES.fetch("village-master"))
      metrics, result = audit_measure { rows.sort_by { |row| c.send(:module_record_sort_value, row) }.map(&:id) }
      sort_results << result
      metrics
    end
    raise "Master sort order changed" unless sort_results[0] == sort_results[1]
    report[:master_sort_15000] = { before: sort_metrics[0], after: sort_metrics[1], outputs_equal: true }

    shared = SharedCatalogueCache.new(shared_directory)
    shared_results = []
    shared_metrics = [false, true].map do |use_shared|
      Rails.cache.clear
      if use_shared
        prewarm = UsersController.new
        prewarm.define_singleton_method(:shared_form_catalogue_cache) { shared }
        prewarm.send(:user_form_options_payload)
        Rails.cache.clear
      end
      c = UsersController.new
      c.define_singleton_method(:shared_form_catalogue_cache) { use_shared ? shared : nil }
      c.define_singleton_method(:build_user_form_options_payload) { raise "Shared fill rebuilt" } if use_shared
      metrics, result = audit_measure { c.send(:user_form_options_payload) }
      shared_results << result
      metrics
    end
    raise "User form output changed" unless shared_results[0] == shared_results[1]
    report[:fresh_worker_user_form_8000_villages] = { before: shared_metrics[0], after_prewarm: shared_metrics[1], outputs_equal: true }
    raise ActiveRecord::Rollback
  end
ensure
  Rails.cache = previous_cache
  FileUtils.remove_entry(shared_directory)
end
puts JSON.pretty_generate(report)
