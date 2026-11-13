# RAILS_ENV=test bundle exec rails runner script/cluster_role_label_performance_audit.rb
# Synthetic objects only; no database writes or external requests.
abort "Use test environment" unless Rails.env.test?
require "open3"

user_type = Struct.new(:full_name, :user_name, :role_name, :role)
users = 1_000.times.map { |i| user_type.new("Person #{i}", "user#{i}", nil, i.even? ? "Cluster Incharge" : "Staff") }
labels = 500.times.flat_map { |i| ["Person #{i}", "missing #{i}"] }
report = []
[ModulesController, VrpsController].each do |klass|
  source, status = Open3.capture2("git", "show", "HEAD:app/controllers/#{klass.name.underscore}.rb")
  raise "Cannot load baseline" unless status.success?
  method = source[/^  def user_record_cluster_incharge_label\?\(label\).*?(?=^  def )/m]
  raise "Missing baseline method" unless method
  baseline = Class.new(klass)
  baseline.class_eval(method)
  results = []
  timings = [baseline, klass].map do |type|
    controller = type.new
    controller.define_singleton_method(:model_ready?) { |_| true }
    controller.instance_variable_set(:@cluster_mapping_users, users)
    controller.instance_variable_set(:@dashboard_cluster_role_users, users)
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results << labels.map { |label| controller.send(:user_record_cluster_incharge_label?, label) }
    { ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
      allocations: GC.stat(:total_allocated_objects) - allocated }
  end
  raise "Role matching changed" unless results[0] == results[1]
  report << { controller: klass.name, users: users.size, labels: labels.size, before: timings[0], after: timings[1] }
end
puts JSON.pretty_generate(note: "Synthetic role lookup CPU benchmark; not full HTTP or production latency", measurements: report)
