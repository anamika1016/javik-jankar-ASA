# Run with RAILS_ENV=test bundle exec rails runner script/performance_audit.rb.
# Synthetic records are rolled back; never run this against live application data.
require "benchmark"
abort "Use RAILS_ENV=test with a dedicated test database" unless Rails.env.test?

def measure_read
  queries = 0
  database_ms = 0.0
  instantiated = 0
  sql = lambda do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    next if %w[SCHEMA TRANSACTION].include?(event.payload[:name]) || event.payload[:cached]
    queries += 1
    database_ms += event.duration
  end
  records = ->(*args) { instantiated += args.last[:record_count] }
  value = nil
  elapsed = Benchmark.realtime do
    ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
      ActiveSupport::Notifications.subscribed(records, "instantiation.active_record") { value = yield }
    end
  end
  [{ ms: (elapsed * 1000).round(2), queries: queries, database_ms: database_ms.round(2), instantiated: instantiated }, value]
end

report = { environment: Rails.env, benchmarks: {}, pages: [] }
ActiveRecord::Base.transaction do
  now = Time.current
  rows = 8_000.times.map do |index|
    { module_slug: "performance-audit", data: { "unrelated" => "x" * 1024, "row" => index }, created_at: now - index, updated_at: now }
  end
  25.times { |index| rows[index][:data]["audit_value"] = "Value #{index}" }
  rows.each_slice(500) { |batch| ModuleRecord.insert_all!(batch) }
  controller = ModulesController.new
  controller.instance_variable_set(:@slug, "state-master")
  expected = controller.send(:active_module_records_scope_for_all_modules).where.not(module_slug: "state-master")
    .order(created_at: :desc).flat_map { |record| %w[audit_value audit_value_name audit_value_title audit_value_code].filter_map { |key| record.data[key].presence } }.uniq
  stats, actual = measure_read { controller.send(:generic_field_options, "Audit Value") }
  raise "Dropdown output changed" unless expected == actual
  report[:benchmarks][:dropdown_8000_records_25_values] = stats.merge(values: actual.size)

  directory = 2_000.times.map { |index| { state: "State #{index}" } } +
    2_000.times.map { |index| { state: "State #{index}", district: "District #{index}", village: "Village #{index}" } }
  stats, compacted = measure_read { controller.send(:compact_lg_directory_rows, directory) }
  raise "Directory output changed" unless compacted == directory.last(2_000)
  report[:benchmarks][:directory_4000_rows] = stats.merge(rows: compacted.size)
  attributes = { aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
    date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current, email: "audit@example.test",
    experience_in_years: 0, father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456",
    mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0, created_at: now, updated_at: now,
    agreement_signature_data: "x" * 4096 }
  Vrp.insert_all!(500.times.map { |index| attributes.merge(name: "Audit JJ #{index}") })
  stats, = measure_read { 10.times { controller.send(:static_field_options, "Month Name") } }
  report[:benchmarks][:ordinary_options_with_500_jjs] = stats
  raise ActiveRecord::Rollback
end

ActiveRecord::Base.transaction do
  admin = User.create!(first_name: "Performance", last_name: "Audit", user_name: "performance_audit_admin",
    email: "performance-audit@example.test", mobile_no: "9876501234", password: "audit-test-password",
    user_type: "admin", status: "Active")
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post("/login", params: { login: admin.user_name, password: "audit-test-password" })
  raise "Audit login failed" unless session.response.redirect? && session.response.location.end_with?("/dashboard")

  paths = ModulesController::MODULES.keys.map { |slug| "/modules/#{slug}" }
  paths.concat(%w[/dashboard /users /users/new /vrps /vrps/new /vrps/approvals /vrp-agreements /afls /target_mappings /asa360-mapping])
  paths.each do |path|
    begin
      stats, = measure_read { session.get(path) }
      report[:pages] << stats.merge(path: path, status: session.response.status, bytes: session.response.body.bytesize)
    rescue StandardError => error
      report[:pages] << { path: path, error: "#{error.class}: #{error.message.lines.first.to_s.strip}" }
    end
  end
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(report)
