# RAILS_ENV=test bundle exec rails runner script/form_location_render_performance_audit.rb
# Dedicated test database only. All synthetic writes are rolled back.
abort "Use a dedicated test database" unless Rails.env.test?
require "benchmark"

def measure_form_read
  queries = 0
  subscriber = ->(*args) { queries += 1 if args.last[:sql].start_with?("SELECT") && !args.last[:cached] }
  result = nil
  ms = Benchmark.realtime do
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { result = yield }
  end * 1000
  [{ ms: ms.round(2), queries: queries }, result]
end

previous_cache = Rails.cache
Rails.cache = ActiveSupport::Cache::MemoryStore.new(size: 64.megabytes)
begin
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.uncached do
      now = Time.current
      8_000.times.each_slice(500) do |indexes|
        ModuleRecord.insert_all!(indexes.map do |index|
          { module_slug: "village-master", created_at: now - index, updated_at: now,
            data: { "state_name" => "Audit State", "district_name" => "Audit District",
              "block_name" => "Audit Block", "gram_panchayat_name" => "Audit GP #{index / 10}",
              "village_name" => "Audit Village #{index} <&\"'", "status" => "Active" } }
        end)
      end
      user = UsersController.new
      user.send(:load_form_options)
      # Recreate the old cached payload: it retained the hierarchy array and
      # serialized/escaped it during every render.
      baseline_user_cache = ActiveSupport::Cache::MemoryStore.new(size: 16.megabytes)
      baseline_payload = user.send(:user_form_options_payload).except(:location_hierarchy_browser_attribute)
      baseline_payload[:location_hierarchy_mappings] = user.instance_variable_get(:@location_hierarchy_mappings)
      baseline_user_cache.write("baseline", baseline_payload)
      VrpsController.new.send(:vrp_location_browser_attribute)
      VrpsController.new.send(:distinct_lg_directory_values, "village_name", "village", state: "Audit State")
      measurements = 3.times.map do
        old_vrp, old_vrp_html = measure_form_read do
          ERB::Util.html_escape(ERB::Util.json_escape(VrpsController.new.send(:location_hierarchy_mappings).to_json))
        end
        new_vrp, new_vrp_html = measure_form_read { VrpsController.new.send(:vrp_location_browser_attribute) }
        old_user, old_user_html = measure_form_read do
          scope = ModuleRecord.where(module_slug: UsersController::FORM_OPTION_SLUGS)
          scope.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
          payload = baseline_user_cache.read("baseline").deep_dup
          ERB::Util.html_escape(ERB::Util.json_escape(payload[:location_hierarchy_mappings].to_json))
        end
        new_user, new_user_html = measure_form_read do
          controller = UsersController.new
          controller.send(:load_form_options)
          controller.instance_variable_get(:@location_hierarchy_browser_attribute)
        end
        raise "Location HTML changed" unless old_vrp_html == new_vrp_html && old_user_html == new_user_html
        old_labels, expected = measure_form_read { VrpsController.new.send(:uncached_distinct_lg_directory_values, "village_name", "village", state: "Audit State") }
        new_labels, actual = measure_form_read { VrpsController.new.send(:distinct_lg_directory_values, "village_name", "village", state: "Audit State") }
        raise "Location labels changed" unless expected == actual
        { vrp_before: old_vrp, vrp_after: new_vrp, user_before: old_user, user_after: new_user,
          labels_before: old_labels, labels_after: new_labels, vrp_attribute_bytes: new_vrp_html.bytesize }
      end
      puts JSON.pretty_generate(note: "Local warm form-data/HTML preparation, not full requests or production latency; 8,000 synthetic villages; writes rolled back", measurements: measurements)
      raise ActiveRecord::Rollback
    end
  end
ensure
  Rails.cache = previous_cache
end
