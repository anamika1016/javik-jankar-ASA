require "test_helper"
require "timeout"

class ModuleRecordReadVersionTest < ActiveSupport::TestCase
  setup do
    @connection = ModuleRecord.connection
    assert ModuleRecordReadVersion.read, "Run db:migrate on the isolated test database to exercise statement triggers"
  end

  test "source stamps track direct insert update move and delete without changing business timestamps" do
    before_a = ModuleRecordReadVersion.read(slugs: ["clock-a"])
    before_b = ModuleRecordReadVersion.read(slugs: ["clock-b"])
    global = ModuleRecordReadVersion.read
    ModuleRecord.insert_all!([{ module_slug: "clock-a", data: { "label" => "A" }, created_at: Time.current, updated_at: Time.current }])
    record = ModuleRecord.find_by!(module_slug: "clock-a")
    refute_equal before_a, ModuleRecordReadVersion.read(slugs: ["clock-a"])
    refute_equal global, ModuleRecordReadVersion.read
    assert_equal before_b, ModuleRecordReadVersion.read(slugs: ["clock-b"])
    timestamp = record.updated_at
    old_version = ModuleRecordReadVersion.read(slugs: ["clock-a"])
    record.update_columns(data: { "label" => "Edited" })
    refute_equal old_version, ModuleRecordReadVersion.read(slugs: ["clock-a"])
    assert_equal timestamp, record.reload.updated_at
    old_version = ModuleRecordReadVersion.read(slugs: ["clock-a"])
    ModuleRecord.where(id: record.id).update_all(module_slug: "clock-b")
    refute_equal old_version, ModuleRecordReadVersion.read(slugs: ["clock-a"])
    refute_equal before_b, ModuleRecordReadVersion.read(slugs: ["clock-b"])
    old_version = ModuleRecordReadVersion.read(slugs: ["clock-b"])
    ModuleRecord.where(id: record.id).delete_all
    refute_equal old_version, ModuleRecordReadVersion.read(slugs: ["clock-b"])
  end

  test "rolled back stamps cannot be reused for a later different payload" do
    record = ModuleRecord.create!(module_slug: "clock-rollback", data: { "label" => "Before" })
    before = ModuleRecordReadVersion.read(slugs: [record.module_slug])
    unpublished = nil
    ModuleRecord.transaction(requires_new: true) do
      record.update_columns(data: { "label" => "Rolled back" })
      unpublished = ModuleRecordReadVersion.read(slugs: [record.module_slug])
      refute_equal before, unpublished
      raise ActiveRecord::Rollback
    end
    assert_equal before, ModuleRecordReadVersion.read(slugs: [record.module_slug])
    record.update_columns(data: { "label" => "Committed later" })
    refute_equal unpublished, ModuleRecordReadVersion.read(slugs: [record.module_slug])
  end

  test "mixed bulk upserts track both moved records and inserted sources" do
    record = ModuleRecord.create!(module_slug: "clock-upsert-old", data: { "label" => "Before" })
    slugs = %w[clock-upsert-old clock-upsert-new clock-upsert-inserted clock-upsert-untouched]
    before = slugs.to_h { |slug| [slug, ModuleRecordReadVersion.read(slugs: [slug])] }
    timestamp = record.updated_at
    ModuleRecord.upsert_all([
      { id: record.id, module_slug: "clock-upsert-new", data: { "label" => "Moved" }, created_at: record.created_at, updated_at: timestamp },
      { id: record.id + 1, module_slug: "clock-upsert-inserted", data: { "label" => "Inserted" }, created_at: record.created_at, updated_at: timestamp }
    ], record_timestamps: false)
    slugs.first(3).each { |slug| refute_equal before.fetch(slug), ModuleRecordReadVersion.read(slugs: [slug]) }
    assert_equal before.fetch(slugs.last), ModuleRecordReadVersion.read(slugs: [slugs.last])
    assert_equal "Moved", record.reload.data["label"]
    assert_equal "clock-upsert-new", record.module_slug
    assert_equal timestamp, record.updated_at
    assert_equal "Inserted", ModuleRecord.find(record.id + 1).data["label"]
  end

  test "truncate changes source and global stamps" do
    ModuleRecord.create!(module_slug: "clock-truncate", data: { "label" => "Before" })
    source = ModuleRecordReadVersion.read(slugs: ["clock-truncate"])
    global = ModuleRecordReadVersion.read
    @connection.execute("TRUNCATE module_records")
    refute_equal source, ModuleRecordReadVersion.read(slugs: ["clock-truncate"])
    refute_equal global, ModuleRecordReadVersion.read
  end

  test "disabled triggers cause a legacy fallback instead of trusting a stale stamp" do
    @connection.execute("ALTER TABLE module_records DISABLE TRIGGER jj_module_record_versions_update")
    assert_nil ModuleRecordReadVersion.read
    assert_equal "legacy", ModuleRecordReadVersion.fetch { "legacy" }
  ensure
    @connection.execute("ALTER TABLE module_records ENABLE TRIGGER jj_module_record_versions_update")
  end

  test "a missing version table safely uses the legacy fingerprint path" do
    @connection.execute("ALTER TABLE module_record_read_versions RENAME TO clock_test_hidden_versions")
    ModuleRecord.connection_pool.schema_cache.clear!
    assert_nil ModuleRecordReadVersion.read
    assert_equal "legacy", ModuleRecordReadVersion.fetch { "legacy" }
  ensure
    @connection.execute("ALTER TABLE clock_test_hidden_versions RENAME TO module_record_read_versions")
    ModuleRecord.connection_pool.schema_cache.clear!
  end

  test "warm version reads do not scan source payloads or fingerprint source rows" do
    statements = []
    callback = ->(*args) { statements << args.last[:sql] if args.last[:sql].start_with?("SELECT") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      3.times { assert ModuleRecordReadVersion.read(slugs: ["village-master", "state-master"]) }
    end
    assert_equal 3, statements.size
    assert statements.all? { |sql| sql.include?("FROM module_record_read_versions") }
    refute statements.any? { |sql| sql.include?("STRING_AGG") || sql.include?("xmin") || sql.include?('FROM "module_records"') }
  end

  test "a source change during a cold revision fill is not published under its old stamp" do
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => "clock-race-training", "status" => "Pending" })
    version = ModuleRecordReadVersion.read(slugs: [TrainingEditApproval::SLUG])
    key = ["training-unapproved-clock-v1", ModuleRecord.connection_pool.db_config.database, version]
    original = TrainingEditApproval.method(:read_unapproved_revision_rows)
    changed = false
    TrainingEditApproval.define_singleton_method(:read_unapproved_revision_rows) do |query|
      rows = original.call(query)
      unless changed
        changed = true
        revision.update_columns(data: revision.data.merge("status" => "Approved"))
      end
      rows
    end
    assert_includes TrainingEditApproval.unapproved_record_ids, "clock-race-training"
    assert_nil TrainingEditApproval::REVISION_READ_CACHE.read(key)
    assert_nil TrainingEditApproval.shared_revision_cache(:read, key)
    refute_includes TrainingEditApproval.unapproved_record_ids, "clock-race-training"
  ensure
    TrainingEditApproval.define_singleton_method(:read_unapproved_revision_rows, original) if original
  end
end

class ModuleRecordReadVersionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "unrelated module writes remain independent and stamps become visible only at commit" do
    assert ModuleRecordReadVersion.read
    first = ModuleRecord.create!(module_slug: "clock-concurrency-a", data: { "label" => "Before A" })
    second = ModuleRecord.create!(module_slug: "clock-concurrency-b", data: { "label" => "Before B" })
    before_a = ModuleRecordReadVersion.read(slugs: [first.module_slug])
    before_b = ModuleRecordReadVersion.read(slugs: [second.module_slug])
    held, release, completed = Queue.new, Queue.new, Queue.new
    writer_a = Thread.new do
      ModuleRecord.connection_pool.with_connection do
        ModuleRecord.transaction do
          ModuleRecord.where(id: first.id).update_all(data: { "label" => "After A" })
          held << true
          release.pop
        end
      end
    end
    Timeout.timeout(5) { held.pop }
    writer_b = Thread.new do
      ModuleRecord.connection_pool.with_connection do
        ModuleRecord.where(id: second.id).update_all(data: { "label" => "After B" })
        completed << true
      end
    end
    Timeout.timeout(5) { completed.pop }
    assert_equal before_a, ModuleRecordReadVersion.read(slugs: [first.module_slug])
    refute_equal before_b, ModuleRecordReadVersion.read(slugs: [second.module_slug])
    assert_equal "Before A", first.reload.data["label"]
    assert_equal "After B", second.reload.data["label"]
    release << true
    writer_a.value
    writer_b.value
    refute_equal before_a, ModuleRecordReadVersion.read(slugs: [first.module_slug])
    assert_equal "After A", first.reload.data["label"]
  ensure
    release << true if release
    [writer_a, writer_b].compact.each do |thread|
      thread.join(10)
      thread.kill if thread.alive?
    end
    ModuleRecord.where(id: [first&.id, second&.id].compact).delete_all
  end
end
