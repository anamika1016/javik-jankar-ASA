# Compare archive-backed temporary views with dedicated storage in a disposable clone.
# No user database changes; the archive drop and temporary login are rolled back.
require "securerandom"
require "nokogiri"
require "net/http"
c = ActiveRecord::Base.connection
abort "Disposable database required" unless c.current_database.start_with?("jj_cutover_validation_")
ActiveRecord.query_transformers.clear
Net::HTTP.prepend(Module.new do
  private
  def connect = raise(SocketError, "External HTTP disabled in storage audit")
end)
def canonical_value(value)
  case value
  when Hash then value.sort.to_h.transform_values { |v| canonical_value(v) }
  when Array then value.map { |v| canonical_value(v) }
  else value
  end
end

def ui_snapshot(response)
  document = Nokogiri::HTML(response.body)
  root = document.at_css(".module-page") || document.at_css("main") || document.at_css("body")
  return { status: response.status, location: response.location } unless root
  root.css('script, style, input[name="authenticity_token"], meta[name="csrf-token"]').remove
  controls = root.css("input, select, textarea").map do |node|
    value = node["value"]
    begin
      value = canonical_value(JSON.parse(value)) if value&.match?(/\A[\[{]/)
    rescue JSON::ParserError
      # Ordinary form text can start with a bracket too.
    end
    [node.name, node["name"], node["type"], value, node["checked"], node["disabled"],
      node.name == "select" ? node.css("option").map { |o| [o["value"], o.text, o["selected"]] } : nil]
  end
  { status: response.status, location: response.location,
    text: root.text.gsub(/\s+/, " ").strip, controls: controls,
    links: root.css("a[href]").map { |a| [a["href"], a.text.strip] } }
end

results = []
new_storage_queries = []
ModulesController.prepend(Module.new do
  def ordered_module_list_scope(scope)
    Thread.current[:archive_order_baseline] ? scope : super
  end
end)
ActiveRecord::Base.transaction do
  name = "cutover_ui_#{SecureRandom.hex(5)}"
  password = SecureRandom.hex(16)
  User.create!(user_name: name, password: password, first_name: "Audit", user_type: "admin", status: "Active")
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! "localhost"
  client.get "/login"
  token = Nokogiri::HTML(client.response.body).at_css('input[name="authenticity_token"]')["value"]
  client.post "/login", params: {login: name, password: password, authenticity_token: token}
  raise "Login failed" unless client.response.redirect? && !client.response.location.end_with?("/login")
  client.get "/farmer360"
  paths = ["/farmer360", "/dashboard"] + ModulesController::MODULES.keys.map { |slug| Rails.application.routes.url_helpers.module_path(slug) }
  baseline = {}
  c.execute("CREATE TEMP VIEW module_entries AS SELECT id, module_slug, data, created_at, updated_at, xmin::text AS xmin, ctid::text AS ctid FROM public.module_records")
  active = ModuleMirrorSql::ACTIVE_FROM_DATA.gsub('data ->>', 'data::jsonb ->>')
  c.execute("CREATE TEMP VIEW module_entry_payloads AS SELECT id, module_slug, data::jsonb AS data, created_at, updated_at, #{active} AS catalogue_active, #{active} AS record_active FROM public.module_records")
  Thread.current[:archive_order_baseline] = true
  paths.each do |path|
    ObjectSpace.each_object(ActiveSupport::Cache::MemoryStore, &:clear)
    client.get path
    baseline[path] = ui_snapshot(client.response)
  end
  Thread.current[:archive_order_baseline] = false
  c.execute("DROP VIEW pg_temp.module_entries")
  c.execute("DROP VIEW pg_temp.module_entry_payloads")
  c.execute("DROP TABLE module_records")
  ModuleRecord.reset_column_information
  subscriber = ->(*args) { sql=args.last[:sql]; new_storage_queries << sql if sql.match?(/\b(?:FROM|JOIN|INTO|UPDATE)\s+(?:public\.)?"?module_records\b/i) }
  ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
    paths.each do |path|
      ObjectSpace.each_object(ActiveSupport::Cache::MemoryStore, &:clear)
      client.get path
      actual = ui_snapshot(client.response)
      results << {path: path, status: client.response.status, equal: actual == baseline[path],
        differing_parts: baseline[path].keys.reject { |key| baseline[path][key] == actual[key] }}
    end
  end
  raise ActiveRecord::Rollback
end
report = {note: "Disposable clone; archive-backed temporary views compared with archive-absent dedicated reads. External HTTP blocked; temporary user and archive drop rolled back. Admin role only.",
  database: c.current_database, total: results.size, matched: results.count { |r| r[:equal] }, archive_application_queries: new_storage_queries.size, results: results}
File.write(Rails.root.join("tmp/dedicated_storage_page_parity.json"), JSON.pretty_generate(report))
puts JSON.pretty_generate(report.except(:results).merge(differences: results.reject { |r| r[:equal] }))
abort "Page parity or archive-dependency failure" if results.any? { |r| !r[:equal] } || new_storage_queries.any?
