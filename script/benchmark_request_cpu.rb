# Synthetic CPU benchmark with complete output parity; performs no database writes.
# Run with bundle exec rails runner script/benchmark_request_cpu.rb
require 'open3'
raise 'Use a local development/test environment' if Rails.env.production?
def legacy_class(klass, file, methods)
  source, status = Open3.capture2('git', 'show', "#{ENV.fetch("PERFORMANCE_BASELINE_REF", "c480b27")}:#{file}")
  raise unless status.success?
  Class.new(klass).tap do |old|
    methods.each do |name|
      start = source.index("  def #{name}(") || source.index("  def #{name}\n")
      finish = source.index("\n  def ", start + 1) || source.rindex("\nend")
      old.class_eval(source[start...finish])
    end
  end
end
def measure
  GC.start
  a=GC.stat(:total_allocated_objects);t=Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result=yield
  [{ms:((Process.clock_gettime(Process::CLOCK_MONOTONIC)-t)*1000).round(2),allocations:GC.stat(:total_allocated_objects)-a},result]
end
old_user=legacy_class(UsersController,'app/controllers/users_controller.rb',%w[location_row active_module_record? truthy_module_flag?])
Row=Struct.new(:id,:data,:created_at,:module_slug)
rows=Array.new(20000) { |i| Row.new(i, {'state_name'=>'State','district_name'=>'District','block_name'=>'Block','gram_panchayat_name'=>'GP','village_name'=>"Village #{i}"},Time.at(i),'village-master') }
outputs=[]
[old_user, UsersController].each do |klass|
  c=klass.new
  c.define_singleton_method(:preload_user_form_module_records!) do
    @ordered_user_form_records={}; @user_form_module_records={'village-master'=>rows}
  end
  metrics,result=measure { c.send(:build_user_form_options_payload) }
  outputs<<result
  puts({stage:klass==old_user ? 'user_cold_before' : 'user_cold_after',**metrics}.to_json)
end
raise 'Form payload changed' unless outputs[0]==outputs[1]
[ModulesController,VrpsController].each do |klass|
  normalizer=klass==ModulesController ? 'normalize_dashboard_user_label' : 'normalize_person_label'
  old=legacy_class(klass,"app/controllers/#{klass.name.underscore}.rb",['cluster_label_matches?',normalizer])
  outputs=[]
  [old,klass].each do |type|
    c=type.new
    metrics,result=measure { Array.new(20000) { |i| c.send(:cluster_label_matches?, "Person #{i%100} Kumar (Cluster)", "Person #{i%100} Kumar") } }
    outputs<<result
    puts({stage:"#{klass.name}_#{type==old ? 'before' : 'after'}",**metrics}.to_json)
  end
  raise 'Visibility comparison changed' unless outputs[0]==outputs[1]
end
puts 'PASS: complete form payload and label results identical; synthetic workload, not HTTP timings'
