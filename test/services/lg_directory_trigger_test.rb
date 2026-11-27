require "test_helper"
# Migrations are not autoloaded. db/schema.rb cannot carry a trigger, so this
# database comes up without one and the test installs the real migration's.
require Rails.root.join("db/migrate/20261123161000_sync_lg_directory_tables")

# The jj_lg_directory_sync trigger, which carries the writes ActiveRecord
# callbacks never see -- insert_all!, update_all, delete_all, raw SQL. The
# dropdowns read these tables now, so this is what stops them going stale.
#
# db/schema.rb cannot carry a trigger, so the migration is run here to install
# the real one. In a deployed environment migrations do that; where they have
# not, ModuleMirror.ready? reports false and every read falls back to
# module_records rather than serving a mirror nothing is filling.
class LgDirectoryTriggerTest < ActiveSupport::TestCase
  setup do
    @migration_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    SyncLgDirectoryTables.new.up
    ModuleMirror.reset_ready!
    assert_trigger_installed "jj_lg_directory_sync_write"
    ModuleRecord.where(module_slug: LgDirectory::SLUGS).delete_all
    LgDirectory.resync!
  end

  teardown do
    SyncLgDirectoryTables.new.down
    ModuleMirror.reset_ready!
    ActiveRecord::Migration.verbose = @migration_verbose
  end

  test "the trigger mirrors an insert_all! that skips callbacks" do
    result = ModuleRecord.insert_all!([{
      module_slug: "village-master",
      data: { "state" => "MP", "block" => "Sausar", "village_name" => "Trigger Village", "status" => "Active" },
      created_at: Time.current, updated_at: Time.current
    }])
    id = result.rows.flatten.first

    row = LgVillage.find_by(id: id)
    assert_not_nil row, "the trigger should have mirrored this without any Ruby help"
    assert_equal "Trigger Village", row.village_name
    assert_equal "Sausar", row.block_name
    assert row.active
  end

  test "the trigger mirrors a delete_all" do
    record = ModuleRecord.create!(module_slug: "block-master",
      data: { "block_name" => "Doomed Block", "status" => "Active" })
    assert_not_nil LgBlock.find_by(id: record.id)

    ModuleRecord.where(id: record.id).delete_all
    assert_nil LgBlock.find_by(id: record.id)
  end

  test "the trigger mirrors an update_all" do
    record = ModuleRecord.create!(module_slug: "block-master",
      data: { "block_name" => "Renamed Block", "status" => "Active" })

    # A Hash, not .to_json: `data` is a serialized attribute, so update_all
    # encodes it once. Passing a String here would store a JSON-encoded JSON
    # string, which ModuleRecord#data could not read back either.
    ModuleRecord.where(id: record.id)
      .update_all(data: { "block_name" => "Renamed Block", "status" => "Inactive" })

    assert_not LgBlock.find(record.id).active
  end

  # An edit that moves a row to a different master has to leave the old table.
  test "the trigger moves a row when its slug changes" do
    record = ModuleRecord.create!(module_slug: "block-master",
      data: { "block_name" => "Mover", "status" => "Active" })
    assert_not_nil LgBlock.find_by(id: record.id)

    record.update!(module_slug: "gram-panchayat-master",
      data: { "gram_panchayat_name" => "Mover", "status" => "Active" })

    assert_nil LgBlock.find_by(id: record.id), "must not be left behind in the old table"
    assert_not_nil LgGramPanchayat.find_by(id: record.id)
  end

  test "the trigger ignores slugs that are not LG masters" do
    assert_nothing_raised do
      ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July" })
    end
  end

  # The trigger and LgDirectory#sync! implement the same mapping from two
  # places; this pins that they agree.
  test "the trigger and the Ruby resync produce the same row" do
    record = ModuleRecord.create!(module_slug: "lg-directory-list", data: {
      "state_name" => "MP", "district_name" => "Pandhurna", "cd_block_name" => "Sausar",
      "cd_block_code" => "0246", "gram_panchayat" => "Gram A", "gp_code" => "03656",
      "village_name" => "Parity Village", "village_code" => "495194", "status" => "Active"
    })
    from_trigger = LgVillage.find(record.id).attributes.except("updated_at")

    LgVillage.where(id: record.id).delete_all
    LgDirectory.resync!(["lg-directory-list"])
    from_ruby = LgVillage.find(record.id).attributes.except("updated_at")

    assert_equal from_trigger, from_ruby
  end

  private

  # Guards against the trigger quietly going missing from db/structure.sql:
  # without it these tests would pass by accident only where callbacks happen
  # to cover the case.
  def assert_trigger_installed(name)
    installed = ModuleRecord.connection.select_value(<<~SQL.squish)
      SELECT COUNT(*) FROM pg_trigger
      WHERE tgrelid = 'module_records'::regclass AND tgname = #{ModuleRecord.connection.quote(name)}
        AND NOT tgisinternal AND tgenabled IN ('O', 'A')
    SQL
    assert_equal 1, installed.to_i, "#{name} must be installed for this test to mean anything"
  end
end
