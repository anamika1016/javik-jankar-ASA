# Recommended release command, before serving the new code:
# RAILS_ENV=production bundle exec rails performance:prepare
# Rerun the read-only warmer after large master imports if needed:
# RAILS_ENV=production bundle exec rails runner script/warm_form_catalogues.rb
# Reads master data and writes versioned caches only; no business data writes
# or external HTTP. Production workers reuse these shared files on first hit.
tasks = {
  module_location_attribute: -> { ModulesController.new.send(:location_hierarchy_browser_attribute) },
  vrp_location_attribute: -> { VrpsController.new.send(:vrp_location_browser_attribute) },
  user_form_options: -> { UsersController.new.send(:user_form_options_payload) },
  lg_directory_rows: -> { ModulesController.new.send(:lg_directory_rows) },
  training_revision_ids: -> { TrainingEditApproval.unapproved_record_ids },
  bill_summary_records: -> { ModulesController.new.send(:cached_jeevika_bill_summary_records) }
}
%w[state-master district-master block-master gram-panchayat-master village-master].each do |slug|
  tasks[slug] = lambda do
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, slug)
    controller.instance_variable_set(:@module, ModulesController::MODULES.fetch(slug))
    controller.send(:cached_location_master_page_attributes, slug)
  end
end
%w[state-master district-master block-master gram-panchayat-master village-master month-master add-activity-group].each do |slug|
  tasks["#{slug}-dropdowns"] = lambda do
    controller = ModulesController.new
    controller.params = ActionController::Parameters.new(slug: slug)
    controller.instance_variable_set(:@slug, slug)
    metadata = ModulesController::MODULES.fetch(slug)
    controller.instance_variable_set(:@module, metadata)
    metadata[:fields].each { |field| controller.send(:module_field_options, field) }
  end
end
tasks.each do |name, task|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  task.call
  puts "#{name}: #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)} ms"
end
