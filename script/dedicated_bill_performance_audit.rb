# Isolated, rollback-only Bill List warm-cache and invalidation audit.
require "securerandom"
require "nokogiri"
c = ActiveRecord::Base.connection
abort "Disposable database required" unless c.current_database.start_with?("jj_cutover_validation_")
ActiveRecord.query_transformers.clear
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

ModulesController.prepend(Module.new do
  def populate_jeevika_bill_process_totals(records)
    Thread.current[:bill_populate_calls] = Thread.current[:bill_populate_calls].to_i + 1
    super
  end
end)
measurements = []
ActiveRecord::Base.transaction do
  login = "bill_cache_#{SecureRandom.hex(5)}"
  password = SecureRandom.hex(16)
  user = User.create!(user_name: login, password: password, first_name: "Audit", user_type: "admin", status: "Active")
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! "localhost"
  client.get "/login"
  token = Nokogiri::HTML(client.response.body).at_css('input[name="authenticity_token"]')["value"]
  client.post "/login", params: {login: login, password: password, authenticity_token: token}
  raise "Login failed" unless client.response.redirect? && !client.response.location.end_with?("/login")
  ObjectSpace.each_object(ActiveSupport::Cache::MemoryStore, &:clear)
  expected = nil
  phases = %w[cold warm warm dependency_write module_write]
  phases.each do |phase|
    if phase == "dependency_write"
      target = TargetMapping.first
      raise "Fixture target required" unless target
      target.update_columns(updated_at: target.updated_at)
    elsif phase == "module_write"
      ModuleEntry.create!(module_slug: "project-master", data: {"project_name"=>"Cache invalidation audit"})
    end
    queries = []
    listener = ->(*args) { event=args.last; queries << event[:sql] if event[:sql].start_with?("SELECT") && event[:name] != "SCHEMA" && !event[:cached] }
    Thread.current[:bill_populate_calls] = 0
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { client.get "/modules/jeevika-jankar-bill-list" }
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round(2)
    raise "Bill page failed" unless client.response.status == 200
    snapshot = ui_snapshot(client.response)
    expected ||= snapshot
    raise "Bill UI changed in #{phase}" unless expected == snapshot
    calls = Thread.current[:bill_populate_calls]
    raise "Warm request recalculated totals" if phase == "warm" && calls != 0
    raise "Write did not invalidate totals" if phase.end_with?("write") && calls == 0
    measurements << {phase: phase, ms: ms, select_queries: queries.size, totals_calculations: calls, ui_equal: true}
  end
  raise ActiveRecord::Rollback
end
report = {database: c.current_database, note: "Local disposable snapshot; admin scope; rollback-only. All visible bill values unchanged across cache hits and invalidations. Not production latency.", measurements: measurements}
File.write(Rails.root.join("tmp/dedicated_bill_performance.json"), JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
