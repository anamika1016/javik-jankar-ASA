require "test_helper"
# Migrations are not autoloaded. db/schema.rb cannot carry a trigger, so this
# database comes up without one and the test installs the real migration's.
require Rails.root.join("db/migrate/20261123171000_sync_module_master_tables")

# The small masters mirrored out of module_records: Month, Stakeholder,
# Stakeholder Person Type, Role, Parent Office, Office Category and Sub Office.
#
# Unlike the LG Directory tables these are not about speed -- there are 37 rows
# between them. They exist so the masters can be read and joined by id, which
# is what lets module_records be retired a slug at a time. So what matters here
# is fidelity: same ids, same payloads, columns always in step.
class ModuleMasterMirrorTest < ActiveSupport::TestCase
  MODELS = [ModuleMonth, ModuleStakeholder, ModuleStakeholderRole, ModuleRole,
    ModuleParentOffice, ModuleOfficeCategory, ModuleSubOffice].freeze

  setup do
    @migration_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    SyncModuleMasterTables.new.up
    ModuleMirror.reset_ready!
    installed = ModuleRecord.connection.select_value(<<~SQL.squish)
      SELECT COUNT(*) FROM pg_trigger
      WHERE tgrelid = 'module_records'::regclass AND tgname = 'jj_module_master_sync_write'
        AND NOT tgisinternal AND tgenabled IN ('O', 'A')
    SQL
    assert_equal 1, installed.to_i, "jj_module_master_sync_write must be installed for this test to mean anything"
    MODELS.each { |model| ModuleRecord.where(module_slug: model.module_slug).delete_all }
  end

  teardown do
    SyncModuleMasterTables.new.down
    ModuleMirror.reset_ready!
    ActiveRecord::Migration.verbose = @migration_verbose
  end

  test "a saved master row is mirrored with its id and payload intact" do
    MODELS.each do |model|
      record = ModuleRecord.create!(module_slug: model.module_slug, data: payload_for(model))
      row = model.find_by(id: record.id)

      assert_not_nil row, model.name
      assert_equal record.data, row.data, model.name
      assert_equal record.id, row.id, "#{model.name} must keep the module record's id"
      assert row.active, model.name
    end
  end

  test "the named columns are derived from the payload" do
    record = ModuleRecord.create!(module_slug: "office-mapping-add", data: {
      "stakeholder_category" => "PAPL", "parent_category" => "HO-PAPL",
      "office_name" => "FCO-C Turekela", "sub_office_name" => "TO- Bongomunda",
      "office_level" => "Block", "status" => "Active"
    })
    row = ModuleSubOffice.find(record.id)

    assert_equal "FCO-C Turekela", row.office_name
    assert_equal "TO- Bongomunda", row.sub_office_name
    assert_equal "HO-PAPL", row.parent_category
    assert_equal "Block", row.office_level
  end

  # Generated columns are recomputed by PostgreSQL, so they cannot be left
  # behind by an edit the way a trigger-maintained copy could be.
  test "editing the payload moves the derived columns with it" do
    record = ModuleRecord.create!(module_slug: "role-name",
      data: { "role_name" => "Before", "stakeholder_role" => "Agronomist", "status" => "Active" })
    assert_equal "Before", ModuleRole.find(record.id).role_name

    record.update!(data: record.data.merge("role_name" => "After"))
    assert_equal "After", ModuleRole.find(record.id).role_name
  end

  test "status drives active exactly as active_module_record? does" do
    [[{ "status" => "Active" }, true], [{ "status" => "" }, true], [{}, true],
     [{ "status" => "Inactive" }, false], [{ "deleted" => "1" }, false],
     [{ "is_deleted" => "true" }, false], [{ "discarded" => "yes" }, false]].each do |flag, expected|
      record = ModuleRecord.create!(module_slug: "month-master",
        data: { "month_name" => "June", "financial_year" => "2026-2027" }.merge(flag))
      assert_equal expected, ModuleMonth.find(record.id).active, flag.inspect
    end
  end

  test "deleting a module record removes the mirrored row" do
    record = ModuleRecord.create!(module_slug: "month-master", data: payload_for(ModuleMonth))
    assert_not_nil ModuleMonth.find_by(id: record.id)

    record.destroy!
    assert_nil ModuleMonth.find_by(id: record.id)
  end

  test "bulk writes are mirrored by the trigger" do
    result = ModuleRecord.insert_all!([{ module_slug: "role-name",
      data: { "role_name" => "Bulk Role", "status" => "Active" },
      created_at: Time.current, updated_at: Time.current }])
    id = result.rows.flatten.first
    assert_equal "Bulk Role", ModuleRole.find(id).role_name

    ModuleRecord.where(id: id).delete_all
    assert_nil ModuleRole.find_by(id: id)
  end

  test "moving a record to another master does not leave it in the old table" do
    record = ModuleRecord.create!(module_slug: "role-name",
      data: { "role_name" => "Mover", "status" => "Active" })
    assert_not_nil ModuleRole.find_by(id: record.id)

    record.update!(module_slug: "stakeholder-role",
      data: { "stakeholder_role" => "Mover", "status" => "Active" })

    assert_nil ModuleRole.find_by(id: record.id)
    assert_not_nil ModuleStakeholderRole.find_by(id: record.id)
  end

  test "option pairs match building them off module_records" do
    3.times { |index| ModuleRecord.create!(module_slug: "month-master",
      data: { "month_name" => "Month #{index}", "financial_year" => "2026-2027", "status" => "Active" }) }
    ModuleRecord.create!(module_slug: "month-master",
      data: { "month_name" => "Hidden", "financial_year" => "2026-2027", "status" => "Inactive" })

    expected = ModuleRecord.where(module_slug: "month-master")
      .order(created_at: :desc, id: :desc)
      .select { |record| record.data["status"].to_s.strip.casecmp?("Active") }
      .map { |record| [record.data["month_name"], record.id] }

    assert_equal expected, ModuleMonth.option_pairs
  end

  test "a malformed payload still mirrors without raising" do
    record = ModuleRecord.create!(module_slug: "month-master", data: "not-an-object")
    row = ModuleMonth.find_by(id: record.id)

    assert_not_nil row
    assert_equal({}, row.data)
    assert_nil row.month_name
  end

  test "unrelated slugs are left alone" do
    assert_nothing_raised do
      ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July" })
    end
  end

  private

  def payload_for(model)
    case model.module_slug
    when "month-master" then { "month_name" => "June", "financial_year" => "2026-2027", "status" => "Active" }
    when "stakeholder-master" then { "stakeholder_name_in_english" => "PAPL", "stakeholder_name_in_hindi" => "PAPL", "status" => "Active" }
    when "stakeholder-role" then { "stakeholder_category" => "PAPL", "stakeholder_role" => "Admin", "status" => "Active" }
    when "role-name" then { "stakeholder_category" => "PAPL", "stakeholder_role" => "Manager_ICS", "role_name" => "Manager ics", "status" => "Active" }
    when "parent-office-add" then { "stakeholder_category" => "PAPL", "parent_office_type" => "Parent Office", "parent_office_name" => "HO-PAPL", "office_level" => "State", "status" => "Active" }
    when "office-category-add" then { "stakeholder_category" => "PAPL", "parent_category" => "FCO-C", "office_name" => "FCO-C Turekela", "office_level" => "District", "status" => "Active" }
    when "office-mapping-add" then { "stakeholder_category" => "PAPL", "parent_category" => "HO-PAPL", "office_name" => "FCO-C Turekela", "sub_office_name" => "TO- Bongomunda", "office_level" => "Block", "status" => "Active" }
    end
  end
end
