# Isolated, rollback-only before/after checks for selected-record navigation.
# RAILS_ENV=test bundle exec rails runner script/module_record_detail_read_audit.rb
require "open3"
require "net/http"
require "nokogiri"
abort "Use the isolated performance database" unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?("jj_performance_test_")
Net::HTTP.prepend(Module.new do
  private
  def connect; raise SocketError, "External HTTP disabled in audit"; end
end)

def original_method(path, name)
  source, status = Open3.capture2("git", "show", "HEAD:#{path}")
  raise "Cannot load original method" unless status.success?
  start = source.index(/^  def #{Regexp.escape(name)}(?:\(|\n)/)
  raise "Missing original method" unless start
  finish = source.index("\n  def ", start + 1)
  source[start...finish]
end

def measured
  queries = 0
  instantiated = 0
  sql = ->(*args) { queries += 1 if args.last[:sql].start_with?("SELECT") && !args.last[:cached] && args.last[:name] != "SCHEMA" }
  inst = ->(*args) { instantiated += args.last[:record_count] }
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nil
  ActiveRecord::Base.uncached do
    ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
      ActiveSupport::Notifications.subscribed(inst, "instantiation.active_record") { result = yield }
    end
  end
  [{ ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2), queries: queries,
     instantiated: instantiated, allocations: GC.stat(:total_allocated_objects) - allocations }, result]
end

baseline_vrp = Class.new(VrpsController)
%w[module_record_label module_record_labels].each do |name|
  baseline_vrp.class_eval(original_method("app/controllers/vrps_controller.rb", name))
end
baseline_module = Class.new(ModulesController)
%w[module_record_values gram_panchayat_name_lookup gram_panchayat_location_records].each do |name|
  baseline_module.class_eval(original_method("app/controllers/modules_controller.rb", name))
end
ModulesController.prepend(Module.new do
  def module_records_required_for_show?
    return true if Thread.current[:audit_sibling_list] && @slug == "other-target"
    super
  end
end)

begin
report = { note: "Synthetic isolated fixtures, external HTTP blocked, rolled back; not production latency", cases: {} }
ActiveRecord::Base.transaction do
  now = Time.current
  5_000.times.each_slice(250) do |batch|
    ModuleRecord.insert_all!(batch.map { |i| { module_slug: "other-target", data: {
      "activity" => "Activity #{i}", "unused_upload" => "x" * 4000
    }, created_at: now, updated_at: now } })
  end
  admin = User.create!(user_name: "detail_read_audit", password: "secret", user_type: "admin", status: "Active", first_name: "Admin")
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post("/login", params: { login: admin.user_name, password: "secret" })
  Thread.current[:audit_sibling_list] = true
  before, old_html = measured { session.get("/modules/other-target"); raise "Page failed" unless session.response.status == 200; session.response.body }
  Thread.current[:audit_sibling_list] = false
  after, new_html = measured { session.get("/modules/other-target"); raise "Page failed" unless session.response.status == 200; session.response.body }
  clean = lambda do |html|
    doc = Nokogiri::HTML(html)
    doc.css('[name="authenticity_token"], meta[name="csrf-token"]').remove
    doc.at_css(".module-page").to_html
  end
  raise "Entry form changed" unless clean.call(old_html) == clean.call(new_html)
  report[:cases][:entry_with_5000_siblings] = { before: before, after: after, rendered_page_equal: true }
  selected = ModuleRecord.where(module_slug: "other-target").first
  url = "/modules/other-target/records/#{selected.id}/edit"
  Thread.current[:audit_sibling_list] = true
  before, old_html = measured { session.get(url); raise "Edit failed" unless session.response.status == 200; session.response.body }
  Thread.current[:audit_sibling_list] = false
  after, new_html = measured { session.get(url); raise "Edit failed" unless session.response.status == 200; session.response.body }
  raise "Edit form changed" unless clean.call(old_html) == clean.call(new_html)
  report[:cases][:edit_with_5000_siblings] = { before: before, after: after, rendered_page_equal: true }

  projects = 200.times.map { |i| ModuleRecord.create!(module_slug: "project-master", data: { "project_name" => "Project #{i}" }) }
  ids = projects.map(&:id).reverse + [projects.first.id, "Legacy label"]
  before, expected = measured { baseline_vrp.new.send(:module_record_labels, "project-master", ids, "project_name") }
  after, actual = measured { VrpsController.new.send(:module_record_labels, "project-master", ids, "project_name") }
  raise "Selected labels changed" unless expected == actual
  report[:cases][:detail_200_selected_labels] = { before: before, after: after, output_equal: true }

  300.times.each_slice(100) do |batch|
    ModuleRecord.insert_all!(batch.map { |i| { module_slug: "gram-panchayat-master", data: {
      "gram_name" => "Gram #{i}", "gp_code" => i.to_s, "state" => "State", "block" => "Block",
      "unused_upload" => "x" * 50_000
    }, created_at: now, updated_at: now } })
    ModuleRecord.insert_all!(batch.map { |i| { module_slug: "ics-master", data: {
      "ics_name" => ["ICS #{i}", "Common"], "name" => i, "unused_upload" => "x" * 50_000
    }, created_at: now, updated_at: now } })
  end
  before, expected = measured { baseline_module.new.send(:module_record_values, "ics-master", "ics_name", "name") }
  after, actual = measured { ModulesController.new.send(:module_record_values, "ics-master", "ics_name", "name") }
  raise "Option values changed" unless expected == actual
  report[:cases][:dropdown_300_large_records] = { before: before, after: after, output_equal: true }
  before, expected = measured { baseline_module.new.send(:gram_panchayat_name_lookup) }
  after, actual = measured { ModulesController.new.send(:gram_panchayat_name_lookup) }
  raise "Gram lookup changed" unless expected == actual
  report[:cases][:gram_lookup_300_large_records] = { before: before, after: after, output_equal: true }
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
ensure
  Thread.current[:audit_sibling_list] = nil
end
