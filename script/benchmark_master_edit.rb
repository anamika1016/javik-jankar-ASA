# Run with rails runner -e test in an isolated jj_performance_test_ database.
# All generated records roll back. Set PERFORMANCE_BASELINE_REF and MASTER_BENCHMARK_ROWS as needed.
require 'open3'
require 'tmpdir'
raise 'isolated test DB required' unless Rails.env.test? && ActiveRecord::Base.connection.current_database.start_with?('jj_performance_test_')
source,status=Open3.capture2('git','show',"#{ENV.fetch("PERFORMANCE_BASELINE_REF", "HEAD")}:app/controllers/modules_controller.rb")
raise unless status.success?
view,status=Open3.capture2('git','show',"#{ENV.fetch("PERFORMANCE_BASELINE_REF", "HEAD")}:app/views/modules/show.html.erb")
raise unless status.success?
methods=%w[server_paginated_master_list? location_master_list_cacheable? values_from_module]
original=methods.to_h { |name| [name, ModulesController.instance_method(name)] }
view_paths=ModulesController.view_paths
previous_cache=Rails.cache
root=Dir.mktmpdir('master-edit-baseline-')
FileUtils.mkdir_p(File.join(root,'modules'))
File.write(File.join(root,'modules','show.html.erb'),view)
def metric
  GC.start
  before=GC.stat(:total_allocated_objects)
  started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result=yield
  [{ms:((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round(2),allocations:GC.stat(:total_allocated_objects)-before},result]
end
begin
  ActiveRecord::Base.transaction do
    user=User.create!(user_name:'master_benchmark_admin',password:'secret',first_name:'Admin',user_type:'admin',status:'Active')
    now=Time.current
    ModuleRecord.insert_all!(Array.new(Integer(ENV.fetch("MASTER_BENCHMARK_ROWS", "2000"))) { |i| {module_slug:'village-master',created_at:now,updated_at:now,
      data:{'village_name'=>format('Village %04d',i),'state_name'=>'State','district_name'=>'District','block_name'=>'Block','gram_panchayat_name'=>'Gram','status'=>'Active'}} })
    record=ModuleRecord.where(module_slug:'village-master').order(:id).last
    session=ActionDispatch::Integration::Session.new(Rails.application)
    session.host! 'www.example.com'
    session.post('/login',params:{login:user.user_name,password:'secret'})
    summaries=[]
    %w[before after].each do |stage|
      if stage=='before'
        methods.each do |name|
          start=source.index("  def #{name}(") || source.index("  def #{name}\n")
          finish=source.index("\n  def ",start+1)
          ModulesController.class_eval(source[start...finish])
        end
        ModulesController.prepend_view_path(root)
      else
        original.each { |name,body| ModulesController.define_method(name,body) }
        ModulesController.view_paths=view_paths
      end
      Rails.cache=ActiveSupport::Cache::MemoryStore.new(size:128.megabytes)
      metrics, response=metric {
        session.get("/modules/village-master/records/#{record.id}/edit")
        session.response
      }
      raise "HTTP #{response.status}: #{response.body[0,200]}" unless response.status==200
      doc=Nokogiri::HTML(response.body)
      fields=doc.css('#module-form input, #module-form select, #module-form textarea').reject { |node| node['name']=='authenticity_token' }.map(&:to_html)
      summaries << fields
      puts({stage:stage,**metrics,bytes:response.body.bytesize,saved_rows:doc.css('#module_saved_records tbody tr').size}.to_json)
      frame_metrics, frame_response=metric {
        session.get("/modules/village-master/records/#{record.id}/edit", params:{page:2}, headers:{"Turbo-Frame"=>"module_saved_records_page"})
        session.response
      }
      raise "Frame HTTP #{frame_response.status}" unless frame_response.status==200
      frame_doc=Nokogiri::HTML(frame_response.body)
      raise 'Frame rebuilt the edit form' if stage=='after' && frame_doc.at_css('#module-form')
      puts({stage:"#{stage}_page_2",**frame_metrics,bytes:frame_response.body.bytesize,saved_rows:frame_doc.css('#module_saved_records tbody tr').size}.to_json)
    end
    raise 'Edit form fields/options changed' unless summaries[0]==summaries[1]
    puts 'PASS: all edit form fields/options identical; only saved table is paginated. Local synthetic HTTP timings, not production.'
    raise ActiveRecord::Rollback
  end
ensure
  original.each { |name,body| ModulesController.define_method(name,body) }
  ModulesController.view_paths=view_paths
  Rails.cache=previous_cache
  FileUtils.remove_entry(root)
end
