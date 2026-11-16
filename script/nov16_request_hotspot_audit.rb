# RAILS_ENV=test bundle exec rails runner script/nov16_request_hotspot_audit.rb
# Dedicated test database only; fixtures roll back and HTTP is disabled.
require "open3"
require "tmpdir"
require "net/http"
abort "Use the isolated performance database" unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?("jj_performance_test_")
Net::HTTP.prepend(Module.new do
  private
  def connect; raise SocketError, "External HTTP disabled in audit"; end
end)

def original_source(path)
  text, status = Open3.capture2("git", "show", "HEAD:#{path}")
  raise "Missing baseline source" unless status.success?
  text
end

def original_method(source, name)
  start = source.index(/^  def (?:self\.)?#{Regexp.escape(name)}(?:\(|\n)/)
  raise "Missing baseline method #{name}" unless start
  finish = source.index(/^  def /, start + 1)
  source[start...finish]
end

def measured
  queries = 0
  callback = ->(*args) { queries += 1 if args.last[:sql].start_with?("SELECT") && !args.last[:cached] && args.last[:name] != "SCHEMA" }
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = nil
  ActiveRecord::Base.uncached do
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { value = yield }
  end
  [{ ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2), queries: queries,
     allocations: GC.stat(:total_allocated_objects) - allocations }, value]
end

legacy_options = original_source("app/services/module_field_options_cache.rb").sub("class ModuleFieldOptionsCache", "class Nov16LegacyFieldOptionsCache")
Object.class_eval(legacy_options)
legacy_controller = Class.new(ModulesController)
source = original_source("app/controllers/modules_controller.rb")
%w[projected_module_field_values module_field_options_revision].each do |name|
  legacy_controller.class_eval(original_method(source, name).gsub("ModuleFieldOptionsCache", "Nov16LegacyFieldOptionsCache"))
end
legacy_revisions = Class.new(TrainingEditApproval)
legacy_revisions.class_eval(original_method(original_source("app/services/training_edit_approval.rb"), "unapproved_record_ids"))
previous_cache = Rails.cache
Rails.cache = ActiveSupport::Cache::MemoryStore.new(size: 128.megabytes)
directory = Dir.mktmpdir("nov16-shared-audit-")
shared = SharedCatalogueCache.new(directory)
report = { note: "Synthetic isolated rollback-only measurements; external HTTP blocked; not production full-page latency", cases: {} }
begin
  ActiveRecord::Base.transaction do
    now = Time.current
    20_000.times.each_slice(500) do |indexes|
      ModuleRecord.insert_all!(indexes.map { |i| { module_slug: "nov16-unrelated", data: { "unrelated" => i }, created_at: now, updated_at: now } })
    end
    8_000.times.each_slice(500) do |indexes|
      ModuleRecord.insert_all!(indexes.map { |i| { module_slug: "village-master", data: {
        "state_name" => "Audit State", "district_name" => "Audit District", "block_name" => "Audit Block",
        "gram_panchayat_name" => "Gram #{i / 10}", "village_name" => "Village #{i}", "status" => "Active"
      }, created_at: now - i, updated_at: now } })
    end
    scope = ModuleRecord.where.not(module_slug: "month-master")
    before, = measured { 20.times { Nov16LegacyFieldOptionsCache.revision(scope) } }
    after, = measured { 20.times { ModuleFieldOptionsCache.revision(scope) } }
    report[:cases][:global_version_20_reads_28000_rows] = { before: before, after: after, after_source_row_scans: 0 }

    %w[financial_year financial_year_name name].each_with_index do |key, i|
      ModuleRecord.create!(module_slug: "nov16-options", data: { key => "Value #{i}" })
    end
    dropdown_values = []
    dropdown_stats = [legacy_controller, ModulesController].map do |type|
      warm = type.new
      warm.instance_variable_set(:@slug, "month-master")
      warm.send(:generic_field_options, "Financial Year")
      stats, value = measured do
        c = type.new
        c.instance_variable_set(:@slug, "month-master")
        c.send(:generic_field_options, "Financial Year")
      end
      dropdown_values << value
      stats
    end
    raise "Dropdown values changed" unless dropdown_values[0] == dropdown_values[1]
    report[:cases][:warm_month_dropdown] = { before: dropdown_stats[0], after: dropdown_stats[1], output_equal: true }

    1_000.times.each_slice(100) do |indexes|
      ModuleRecord.insert_all!(indexes.map { |i| { module_slug: TrainingEditApproval::SLUG,
        data: { "record_id" => (i / 2).to_s, "status" => i % 5 == 0 ? "Approved" : "Pending", "before" => { "photo" => "x" * 3000 } },
        created_at: now, updated_at: now } })
    end
    expected = legacy_revisions.unapproved_record_ids
    raise "Audit must cover blocked trainings" if expected.empty?
    raise "Latest revision semantics changed" unless expected == TrainingEditApproval.unapproved_record_ids
    before, = measured { 20.times { legacy_revisions.unapproved_record_ids } }
    after, = measured { 20.times { TrainingEditApproval.unapproved_record_ids } }
    report[:cases][:warm_dashboard_revision_20_reads] = { before: before, after: after, output_equal: true }

    users = []
    user_stats = [false, true].map do |prewarm|
      Rails.cache.clear
      if prewarm
        c = UsersController.new
        c.define_singleton_method(:shared_form_catalogue_cache) { shared }
        c.send(:user_form_options_payload)
        Rails.cache.clear
      end
      c = UsersController.new
      c.define_singleton_method(:shared_form_catalogue_cache) { prewarm ? shared : nil }
      c.define_singleton_method(:build_user_form_options_payload) { raise "Shared value rebuilt" } if prewarm
      stats, value = measured { c.send(:user_form_options_payload) }
      users << value
      stats
    end
    raise "User form payload changed" unless users[0] == users[1]
    report[:cases][:user_catalogue_cold_vs_prewarmed_worker] = { cold: user_stats[0], prewarmed: user_stats[1], output_equal: true }

    ids = 15_000.times.map(&:to_s)
    selected = 5_000.times.map { |i| (i + 10_000).to_s }
    c = ModulesController.new
    c.define_singleton_method(:module_cluster_visible_vrp_id_strings) { ids }
    before, expected = measured { selected.map { |id| ids.include?(id) } }
    after, actual = measured { selected.map { |id| c.send(:module_cluster_visible_vrp_id?, id) } }
    raise "Exact ID membership changed" unless expected == actual
    report[:cases][:visibility_5000_checks_15000_cluster_ids] = { before: before, after: after, output_equal: true }
    raise ActiveRecord::Rollback
  end
ensure
  Rails.cache = previous_cache
  FileUtils.remove_entry(directory)
end
puts JSON.pretty_generate(report)
