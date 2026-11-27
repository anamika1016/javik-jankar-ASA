# Run ONLY against a disposable clone, never development or production.
# bin/rails runner script/dedicated_storage_validation.rb
require "securerandom"
require "timeout"
c = ActiveRecord::Base.connection
abort "Disposable cutover database required" unless c.current_database.start_with?("jj_cutover_validation_")
fields = "id, module_slug, data, created_at, updated_at"
original = c.select_value("SELECT COUNT(*) FROM module_records").to_i
mismatches = c.select_value(<<~SQL).to_i
  SELECT COUNT(*) FROM (
    (SELECT #{fields} FROM module_records EXCEPT SELECT #{fields} FROM module_entries)
    UNION ALL
    (SELECT #{fields} FROM module_entries EXCEPT SELECT #{fields} FROM module_records)
  ) differences
SQL
raise "Byte-level backfill mismatch: #{mismatches}" unless mismatches.zero?
slugs = c.select_values("SELECT slug FROM module_entry_sources ORDER BY slug")
old_queries = []
subscriber = ->(*args) do
  sql = args.last[:sql]
  old_queries << sql if sql.match?(/\b(?:FROM|JOIN|INTO|UPDATE)\s+(?:public\.)?"?module_records\b/i)
end
checks = []
ActiveRecord::Base.transaction do
  c.execute("DROP TABLE module_records")
  ModuleRecord.reset_column_information
  ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
    raise "Count mismatch without archive" unless ModuleEntry.count == original
    ids = []
    slugs.each do |slug|
      record = ModuleEntry.create!(module_slug: slug, data: {"validation" => SecureRandom.hex(8), "status" => "Active"})
      ids << record.id
      raise "Public attributes changed" unless record.attributes.keys.sort == %w[created_at data id module_slug updated_at]
      record.with_lock { record.update!(data: record.data.merge("edited" => ["हिंदी", false, nil])) }
      raise "Update/lock failed for #{slug}" unless record.reload.data["edited"] == ["हिंदी", false, nil]
      record.destroy!
      raise "Deletion failed" if ModuleEntry.exists?(record.id)
    end
    raise "IDs reused across tables" unless ids.uniq.size == ids.size
    checks << "CRUD and physical row locking for all #{slugs.size} configured types"

    bulk = ModuleEntry.insert_all!([
      {module_slug: "project-master", data: {"project_name" => "Bulk A"}},
      {module_slug: "training-topic-mapping", data: {"training_topic" => "Bulk B"}}
    ])
    raise "Bulk ID result changed" unless bulk.rows.size == 2 && bulk.rows.flatten.uniq.size == 2
    ModuleEntry.where(id: bulk.rows.flatten).update_all(data: {"bulk_update" => true})
    raise "Bulk update failed" unless ModuleEntry.where(id: bulk.rows.flatten).all? { |r| r.data == {"bulk_update"=>true} }
    ModuleEntry.where(id: bulk.rows.flatten).delete_all
    checks << "bulk insert IDs, bulk update and delete"

    record = ModuleEntry.create!(module_slug: "project-master", data: {"project_name"=>"Moves"})
    record.update!(module_slug: "person-type")
    raise "Slug move failed" unless record.reload.module_slug == "person-type"
    record.destroy!
    checks << "slug moves preserve IDs"

    ["scalar string", ["array", 1], false, 2].each do |payload|
      row = ModuleEntry.new(module_slug: "project-master", data: payload)
      row.save!(validate: false)
      raise "Legacy JSON scalar changed" unless row.reload.data == payload
      row.destroy!
    end
    checks << "raw JSON text, scalars, arrays and Unicode"

    actor = ModuleEntry.create!(module_slug: "new-user", data: {"user_name"=>"validation_#{SecureRandom.hex(6)}", "password"=>"Before", "status"=>"Active"})
    token = ApiAuthToken.encode(actor)
    raise "Token identity label changed" unless ApiAuthToken.decode(token)["record_type"] == "ModuleRecord"
    raise "Token lookup failed" unless ApiAuthToken.find_user(token)&.id == actor.id
    ApiPasswordReset.update_password!(actor, "After")
    raise "Password reset failed" unless actor.reload.data["password"] == "After"
    actor.destroy!
    checks << "existing token identity and password reset"

    before = ModuleRecordReadVersion.read(dependencies: %w[afls users vrps target_mappings])
    raise "Version stamps unavailable" unless before
    changed = ModuleEntry.create!(module_slug: "project-master", data: {"project_name"=>"Invalidates"})
    raise "Module write did not invalidate" if before == ModuleRecordReadVersion.read(dependencies: %w[afls users vrps target_mappings])
    before = ModuleRecordReadVersion.read(dependencies: %w[afls users vrps target_mappings])
    user = User.create!(user_name: "dependency_#{SecureRandom.hex(6)}", password: "secret", first_name: "Audit", user_type: "admin", status: "Active")
    raise "Dependency write did not invalidate" if before == ModuleRecordReadVersion.read(dependencies: %w[afls users vrps target_mappings])
    changed.destroy!
    user.destroy!
    checks << "transactional module and dependency cache invalidation"
    raise "Archive query detected: #{old_queries.size}" if old_queries.any?
  end
  raise ActiveRecord::Rollback
end
raise "Archive was changed" unless c.select_value("SELECT COUNT(*) FROM module_records").to_i == original

# Committed disposable fixture: the second approver must wait and reload the
# first approver's committed value, rather than overwriting it from an old read.
locked = ModuleEntry.create!(module_slug: "project-master", data: {"lock_counter"=>0})
entered = Queue.new
release = Queue.new
second_entered = Queue.new
begin
  first = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      ModuleEntry.find(locked.id).with_lock do |record|
        # with_lock yields no argument; fetch the same locked row for the edit.
        entered << true
        release.pop
        row = ModuleEntry.find(locked.id)
        row.update!(data: {"lock_counter"=>row.data["lock_counter"] + 1})
      end
    end
  end
  Timeout.timeout(5) { entered.pop }
  second = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      row = ModuleEntry.find(locked.id)
      row.with_lock do
        second_entered << true
        row.update!(data: {"lock_counter"=>row.data["lock_counter"] + 1})
      end
    end
  end
  begin
    Timeout.timeout(0.2) { second_entered.pop }
    raise "Second writer entered an already-locked row"
  rescue Timeout::Error
    # Expected: the physical row lock is still held by the first writer.
  end
  release << true
  Timeout.timeout(5) { first.value; second.value }
  raise "Concurrent update was lost" unless locked.reload.data["lock_counter"] == 2
  checks << "concurrent writers serialize and reload without lost updates"
ensure
  release << true
  first&.join(5)
  second&.join(5)
  locked.destroy! if locked.persisted?
end
report = {database: c.current_database, original_rows: original, exact_backfill_mismatches: mismatches,
  configured_types: slugs.size, archive_application_queries: old_queries.size,
  archive_preserved: true, checks: checks}
File.write(Rails.root.join("tmp/dedicated_storage_validation.json"), JSON.pretty_generate(report))
File.write(Rails.root.join("tmp/dedicated_storage_validation_#{c.current_database}.json"), JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
