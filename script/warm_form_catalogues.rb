# Run after deploying/restarting and after large master imports:
# RAILS_ENV=production bundle exec rails runner script/warm_form_catalogues.rb
# Reads master data and writes versioned caches only; no business data writes
# or external HTTP. Production workers reuse these shared files on first hit.
tasks = {
  module_location_attribute: -> { ModulesController.new.send(:location_hierarchy_browser_attribute) },
  vrp_location_attribute: -> { VrpsController.new.send(:vrp_location_browser_attribute) },
  user_form_options: -> { UsersController.new.send(:user_form_options_payload) },
  lg_directory_rows: -> { ModulesController.new.send(:lg_directory_rows) }
}
%w[state-master district-master block-master gram-panchayat-master village-master].each do |slug|
  tasks[slug] = lambda do
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, slug)
    controller.instance_variable_set(:@module, ModulesController::MODULES.fetch(slug))
    controller.send(:cached_location_master_page_attributes, slug)
  end
end
tasks.each do |name, task|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  task.call
  puts "#{name}: #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)} ms"
end
