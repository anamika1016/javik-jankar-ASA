require "test_helper"
require Rails.root.join("db/migrate/20261123161000_sync_lg_directory_tables")
require Rails.root.join("db/migrate/20261123171000_sync_module_master_tables")
require Rails.root.join("db/migrate/20261124140000_preserve_module_mirror_identity_and_order")

class ModuleMirrorSyncIntegrityTest < ActiveSupport::TestCase
  setup do
    @verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    SyncLgDirectoryTables.new.up
    SyncModuleMasterTables.new.up
    PreserveModuleMirrorIdentityAndOrder.new.up
  end

  teardown do
    PreserveModuleMirrorIdentityAndOrder.new.down
    SyncLgDirectoryTables.new.down
    SyncModuleMasterTables.new.down
    ModuleMirror.reset_ready!
    ActiveRecord::Migration.verbose = @verbose
  end

  test "bulk timestamp edits preserve creation order in both mirror families" do
    [["block-master", LgBlock], ["month-master", ModuleMonth]].each do |slug, model|
      first = ModuleRecord.create!(module_slug: slug, data: { "label" => "First" }, created_at: 2.days.ago)
      second = ModuleRecord.create!(module_slug: slug, data: { "label" => "Second" }, created_at: 1.day.ago)
      changed_time = Time.current.change(usec: 0)
      ModuleRecord.where(id: first.id).update_all(created_at: changed_time)
      assert_equal changed_time, model.find(first.id).created_at
      ids = [first.id, second.id]
      assert_equal ModuleRecord.where(id: ids).order(created_at: :desc).pluck(:id),
        model.where(id: ids).order(created_at: :desc).pluck(:id)
    end
  end

  test "primary key edits remove the old mirrored id" do
    [["block-master", LgBlock], ["month-master", ModuleMonth]].each do |slug, model|
      row = ModuleRecord.create!(module_slug: slug, data: { "label" => "Moves" })
      next_id = ModuleRecord.connection.select_value("SELECT nextval(pg_get_serial_sequence('module_records', 'id'))").to_i
      ModuleRecord.where(id: row.id).update_all(id: next_id)
      assert_nil model.find_by(id: row.id)
      assert_equal row.data, model.find(next_id).data
    end
  end

  test "sync remains transactional and deletion removes the dedicated row" do
    record = ModuleRecord.create!(module_slug: "month-master", data: { "month_name" => "Before" })
    ModuleRecord.transaction(requires_new: true) do
      record.update!(data: { "month_name" => "After" })
      assert_equal "After", ModuleMonth.find(record.id).month_name
      raise ActiveRecord::Rollback
    end
    assert_equal "Before", ModuleMonth.find(record.id).month_name
    record.reload.destroy!
    assert_nil ModuleMonth.find_by(id: record.id)
  end

  test "truncating the source cannot leave readable orphaned mirror rows" do
    ModuleRecord.create!(module_slug: "block-master", data: { "block_name" => "Block" })
    ModuleRecord.create!(module_slug: "month-master", data: { "month_name" => "June" })
    ModuleRecord.connection.execute("TRUNCATE module_records")
    assert_empty LgBlock.all
    assert_empty ModuleMonth.all
  end

  test "the forward sync patch can be rolled back and reapplied" do
    migration = PreserveModuleMirrorIdentityAndOrder.new
    migration.down
    migration.up
    migration.up
    definition = ModuleRecord.connection.select_value("SELECT pg_get_functiondef('jj_module_master_sync()'::regprocedure)")
    assert_includes definition, PreserveModuleMirrorIdentityAndOrder::NEW_VALUES
  end

  test "the migration repairs a missed backfill write without changing business data or timestamps" do
    record = ModuleRecord.create!(module_slug: "month-master", data: { "month_name" => "June" })
    expected = record.attributes
    ModuleMonth.where(id: record.id).delete_all
    PreserveModuleMirrorIdentityAndOrder.new.up
    assert_equal expected, record.reload.attributes
    assert_equal record.data, ModuleMonth.find(record.id).data

    ModuleMonth.where(id: record.id).update_all(data: { "month_name" => "Stale" })
    PreserveModuleMirrorIdentityAndOrder.new.up
    assert_equal expected, record.reload.attributes
    assert_equal record.data, ModuleMonth.find(record.id).data
  end

  test "a stale routing function cannot make an unmaintained mirror readable" do
    connection = ModuleRecord.connection
    mapping = ModuleMirror::SLUG_MODELS.reject { |_slug, model| model.table_name.start_with?("lg_") }
    cases = mapping.map { |slug, model| "WHEN #{connection.quote(slug)} THEN #{connection.quote(model.table_name)}" }.join(" ")
    connection.execute("CREATE OR REPLACE FUNCTION jj_module_master_table(slug text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT CASE slug #{cases} ELSE NULL END $$")
    ModuleMirror.reset_ready!
    assert ModuleMirror.ready?

    connection.execute("CREATE OR REPLACE FUNCTION jj_module_master_table(slug text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT NULL::text $$")
    ModuleMirror.reset_ready!
    refute ModuleMirror.ready?
    record = ModuleRecord.create!(module_slug: "month-master", data: { "month_name" => "Fallback" })
    assert_equal record.data, ModuleMirror.read_scope("month-master").find(record.id).data
  end
end
