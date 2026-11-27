# Local, rollback-only menu comparison. No production access or external HTTP.
# bin/rails runner --skip-executor script/module_transition_page_audit.rb
require "securerandom"
require "nokogiri"
require "net/http"
abort "Use local development only" unless Rails.env.development?
Net::HTTP.prepend(Module.new do
  private
  def connect = raise(SocketError, "External HTTP disabled in menu audit")
end)
ActiveRecord.query_transformers.clear
Rails.cache = ActiveSupport::Cache::MemoryStore.new

# Compare visible text, submitted values/options and record links. Ignore CSRF
# randomness, JS source formatting and JSON object key order, not array order.
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

original_ready = ModuleMirror.method(:ready?)
ModuleMirror.define_singleton_method(:ready?) { Thread.current[:audit_legacy_modules] ? false : original_ready.call }
results = []
begin
  ActiveRecord::Base.transaction do
    username = "module_audit_#{SecureRandom.hex(5)}"
    password = SecureRandom.hex(16)
    User.create!(user_name: username, password: password, first_name: "Read audit", user_type: "admin", status: "Active")
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! "localhost"
    client.get "/login"
    token = Nokogiri::HTML(client.response.body).at_css('input[name="authenticity_token"]')["value"]
    client.post "/login", params: { login: username, password: password, authenticity_token: token }
    raise "Audit login failed" unless client.response.redirect? && !client.response.location.end_with?("/login")
    client.get "/farmer360"
    paths = ["/farmer360"] + ModulesController::MODULES.keys.map { |slug| Rails.application.routes.url_helpers.module_path(slug) }
    paths.each do |path|
      snapshots = {}
      timings = {}
      [true, false].each do |legacy|
        Thread.current[:audit_legacy_modules] = legacy
        ObjectSpace.each_object(ActiveSupport::Cache::MemoryStore, &:clear)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        client.get path
        mode = legacy ? :legacy : :dedicated
        timings[mode] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
        snapshots[mode] = ui_snapshot(client.response)
      end
      results << { path: path, equal: snapshots[:legacy] == snapshots[:dedicated],
        statuses: snapshots.transform_values { |s| s[:status] }, ms: timings,
        differing_parts: snapshots[:legacy].keys.reject { |key| snapshots[:legacy][key] == snapshots[:dedicated][key] } }
    end
    raise ActiveRecord::Rollback
  end
ensure
  Thread.current[:audit_legacy_modules] = nil
  ModuleMirror.define_singleton_method(:ready?, original_ready)
end
report = { note: "Local admin menu UI comparison; cache cleared for each mode; external HTTP blocked; temporary user rolled back. Not production latency or every role/mutation.",
  total: results.size, matched: results.count { |r| r[:equal] }, results: results }
File.write(Rails.root.join("tmp/module_transition_page_parity.json"), JSON.pretty_generate(report))
puts JSON.pretty_generate(report.except(:results).merge(differences: results.reject { |r| r[:equal] }))
abort "Rendered UI differences require review" unless results.all? { |r| r[:equal] }
