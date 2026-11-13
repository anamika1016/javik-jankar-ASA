# CPU-only synthetic candidate selection. No database reads/writes required.
abort "Use test environment" unless Rails.env.test?
require "open3"
source, status = Open3.capture2("git", "show", "HEAD:app/controllers/modules_controller.rb")
raise "Cannot load baseline" unless status.success?
legacy = Class.new(ModulesController)
start = source.index("  def dashboard_training_candidates_for_target(")
finish = source.index("\n  def ", start + 1)
legacy.class_eval(source[start...finish])
row = Struct.new(:id, :data)
owner = Struct.new(:id, :name, :user_name, :mobile_no)
target = Struct.new(:month_name, :vrp)
records = 3_000.times.map { |i| row.new(i, { "jeevika_jankar_id" => i % 6 == 0 ? nil : (i % 100).to_s }) }
targets = 100.times.flat_map do |i|
  person = owner.new(i, "Person #{i}", "login#{i}", "phone#{i}")
  Array.new(10) { target.new("November", person) }
end
results = []
measurements = [legacy, ModulesController].map do |type|
  c = type.new
  c.define_singleton_method(:dashboard_training_form_records_for_month) { |_| records }
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  results << targets.map { |item| c.send(:dashboard_training_candidates_for_target, item) }
  { ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
    allocations: GC.stat(:total_allocated_objects) - allocated }
end
raise "Candidate output/order changed" unless results[0] == results[1]
puts JSON.pretty_generate(note: "Synthetic candidate selection CPU benchmark; not HTTP/production timing",
  records: records.size, owners: 100, targets: targets.size,
  before: measurements[0], after: measurements[1], outputs_equal: true)
