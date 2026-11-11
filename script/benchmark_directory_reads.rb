# Run with rails runner -e test in an isolated jj_performance_test_ database.
# Generated records are always rolled back; compares against PERFORMANCE_BASELINE_REF (default HEAD).
require 'open3'
raise 'isolated test database required' unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?('jj_performance_test_')
source, status = Open3.capture2('git', 'show', "#{ENV.fetch("PERFORMANCE_BASELINE_REF", "HEAD")}:app/controllers/modules_controller.rb")
raise unless status.success?
legacy = Class.new(ModulesController)
%w[module_records_required_for_show? lg_directory_matching_records].each do |name|
  start = source.index("  def #{name}(") || source.index("  def #{name}\n")
  finish = source.index("\n  def ", start + 1)
  legacy.class_eval(source[start...finish])
end
def measure
  GC.start
  objects = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = yield
  [{ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round(2), objects: GC.stat(:total_allocated_objects)-objects}, value]
end
def controller(klass)
  c=klass.new
  c.request=ActionDispatch::TestRequest.create
  c.params=ActionController::Parameters.new(slug:'lg-directory-list')
  c.send(:load_module!)
  c.define_singleton_method(:admin_dashboard_user?) { true }
  c
end
ActiveRecord::Base.transaction do
  now=Time.current
  ModuleRecord.insert_all!(Array.new(15136) { |i| {module_slug:'lg-directory-list',created_at:now,updated_at:now,
    data:{'state_name'=>'State','district_name'=>'District','village_name'=>"Village #{i}",'status'=>'Active','unused'=>'x'*1000}} })
  output=[]
  [legacy,ModulesController].each do |klass|
    Rails.cache=ActiveSupport::Cache::MemoryStore.new(size:128.megabytes)
    ModulesController::LG_DIRECTORY_MEMORY_CACHE.clear
    c=controller(klass)
    metrics, result=ActiveRecord::Base.uncached { measure {
      c.send(:module_records) if c.send(:module_records_required_for_show?)
      c.send(:prepare_lg_directory_data)
      c.instance_variable_get(:@lg_directory_rows)
    } }
    output << result
    puts({stage:klass==legacy ? 'directory_cold_before' : 'directory_cold_after', **metrics, rows:result.size}.to_json)
  end
  raise 'Directory payload changed' unless output[0]==output[1]
  selection=ModuleRecord.where(module_slug:'lg-directory-list').limit(1000).to_a
  matched=[]
  [legacy,ModulesController].each do |klass|
    metrics, result=ActiveRecord::Base.uncached { measure { controller(klass).send(:lg_directory_matching_records,selection).map(&:id) } }
    matched << result
    puts({stage:klass==legacy ? 'bulk_1000_before' : 'bulk_1000_after', **metrics, matches:result.size}.to_json)
  end
  raise 'Bulk selection changed' unless matched[0]==matched[1]
  puts 'PASS: complete directory rows and bulk selection/order match HEAD; synthetic local timings, no HTTP rendering.'
  raise ActiveRecord::Rollback
end
