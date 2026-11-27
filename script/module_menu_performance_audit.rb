# Local navigation SQL profile; temporary login is rolled back.
# bin/rails runner --skip-executor script/module_menu_performance_audit.rb
require 'securerandom'
require 'net/http'
abort 'Use local development only' unless Rails.env.development?
Net::HTTP.prepend(Module.new do
  private
  def connect = raise(SocketError, 'External HTTP disabled in menu audit')
end)
ActiveRecord.query_transformers.clear
results = []
ActiveRecord::Base.transaction do
  username = "read_audit_#{SecureRandom.hex(5)}"
  password = SecureRandom.hex(16)
  User.create!(user_name: username, password: password, first_name: 'Read audit', user_type: 'admin', status: 'Active')
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  client.get '/login'
  token = Nokogiri::HTML(client.response.body).at_css('input[name=authenticity_token]')['value']
  client.post '/login', params: { login: username, password: password, authenticity_token: token }
  abort "Audit login failed: #{client.response.status}" unless client.response.redirect? && !client.response.location.end_with?('/login')
  paths = ['/farmer360'] + ModulesController::MODULES.keys.map { |slug| Rails.application.routes.url_helpers.module_path(slug) }
  (paths + paths).each_with_index do |path, index|
    queries = []
    listener = ->(*args) do
      event = args.last
      if event[:sql].start_with?("SELECT") && event[:name] != "SCHEMA" && !event[:cached]
        fingerprint = event[:sql].gsub(/'(?:''|[^'])*'/, "?").gsub(/\$\d+/, "?").gsub(/\s+/, " ")
        queries << { sql: fingerprint, ms: ((args[2]-args[1])*1000).round(2) }
      end
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { client.get path }
      results << { path: path, pass: index < paths.size ? "cold" : "warm", status: client.response.status,
        query_count: queries.size, sql_ms: queries.sum { |q| q[:ms] }.round(2),
        repeated: queries.group_by { |q| q[:sql] }.filter_map { |sql, qs| {count: qs.size, ms: qs.sum { |q| q[:ms] }.round(2), sql: sql} if qs.size > 2 }.sort_by { |q| -q[:count] }.first(5),
        slow_queries: queries.sort_by { |q| -q[:ms] }.first(5),
        ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)*1000).round }
    rescue => e
      results << { path: path, error: e.class.name }
    end
  end
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(total: results.size, statuses: results.group_by { |r| r[:status] || r[:error] }.transform_values(&:size), slowest: results.sort_by { |r| -r.fetch(:ms,0) }.first(10).map { |r| r.slice(:path, :pass, :status, :ms, :query_count, :sql_ms) })
File.write(Rails.root.join('tmp/module_menu_performance_audit.json'), JSON.pretty_generate(
  note: 'Local admin first/repeated menu navigation; shared caches warm along the sequence; external HTTP blocked; temporary user rolled back. Not production latency.',
  results: results))
