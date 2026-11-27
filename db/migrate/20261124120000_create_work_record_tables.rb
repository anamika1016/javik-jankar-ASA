require Rails.root.join("db/migrate/20261123171000_sync_module_master_tables")
require Rails.root.join("db/migrate/20261124100000_create_activity_and_access_tables")

class CreateWorkRecordTables < ActiveRecord::Migration[8.1]
  # The last of the module_records slugs that hold their own data, on the same
  # pattern as the earlier batches: module_records.id kept as the primary key,
  # payload kept verbatim in `data`, named columns generated from it.
  #
  # Seven tables, for twenty-three screens that were asked for. The rest are
  # already real tables or are list views of a slug that is:
  #
  #   Already their own table   Jeevika Jankar Registration / List / Approval
  #                             Queue and Accepted Agreement are `vrps`;
  #                             AFL Upload is `afls`; Target Mapping Master,
  #                             Recent Target Mappings and JJ Mapped Farmers
  #                             are `target_mappings`. Nothing to move.
  #
  #   List views of a slug      Training Form List, Other Target List, Other
  #                             Target with Farmer List, Approval List, Bill
  #                             List, Payment List, Payment List Detail and
  #                             Completed Payment List all read another slug's
  #                             rows (modules_controller's list-source map) and
  #                             hold none of their own. They follow their source
  #                             automatically.
  #
  # Unlike the master tables, two of these are big enough for the move to be
  # worth something on its own: training-form is 887 rows at ~2 kB, and
  # jeevika-jankar-bill-process is 110 rows at ~75 kB each -- 8 MB, the largest
  # payload in the database by a wide margin.

  TABLES = {
    "module_vrp_types" => {
      slug: "add-vrp-type",
      columns: { "vrp_type_name" => "vrp_type_name" },
      indexes: []
    },
    "module_approvals" => {
      slug: "approval-master",
      columns: { "module_name" => "module_name", "approval_level" => "approval_level",
                 "stakeholder_role" => "stakeholder_role", "role_name" => "role_name" },
      indexes: [["module_name", "approval_level"]]
    },
    "module_trainings" => {
      slug: "training-form",
      columns: { "month" => "month", "main_activity" => "main_activity",
                 "sub_activity" => "sub_activity", "training_method" => "training_method",
                 "main_activity_type" => "main_activity_type",
                 "jeevika_jankar_id" => "jeevika_jankar_id",
                 "cluster_coordinator_name" => "cluster_coordinator_name" },
      # The dashboard groups training entries by month and by the JJ who ran
      # them, and filters on training_method; those are the hot lookups.
      indexes: [["month", "training_method"], ["jeevika_jankar_id", "month"], ["main_activity_type"]]
    },
    "module_other_targets" => {
      slug: "other-target",
      columns: { "month" => "month", "jeevika_jankar_id" => "jeevika_jankar_id",
                 "fcoc_name" => "fcoc_name", "ics_name" => "ics_name",
                 "target_mapping_id" => "target_mapping_id" },
      indexes: [["month"], ["target_mapping_id"]]
    },
    "module_other_farmer_targets" => {
      slug: "other-target-with-farmer",
      columns: { "month" => "month", "jeevika_jankar_id" => "jeevika_jankar_id",
                 "fcoc_name" => "fcoc_name", "target_mapping_id" => "target_mapping_id" },
      indexes: [["month"], ["target_mapping_id"]]
    },
    "module_bills" => {
      slug: "jeevika-jankar-bill-process",
      columns: { "bill_month" => "bill_month", "select_vrp" => "select_vrp",
                 "bill_status" => "status", "grand_total" => "grand_total" },
      workflow_status: true,
      # Bills are listed by month and resolved by the JJ they belong to.
      indexes: [["bill_month"], ["select_vrp", "bill_month"]]
    },
    "module_payment_details" => {
      slug: "jeevika-jankar-payment-detail",
      columns: { "bill_month" => "bill_month", "select_vrp" => "select_vrp",
                 "bill_status" => "status" },
      workflow_status: true,
      indexes: [["bill_month"]]
    }
  }.freeze

  def up
    TABLES.each do |table, config|
      create_table table, id: false do |t|
        t.primary_key :id, :bigint, default: nil
        t.jsonb :data, null: false, default: {}
        t.timestamps
      end

      config[:columns].each do |column, key|
        execute <<~SQL.squish
          ALTER TABLE #{table}
          ADD COLUMN #{column} text
          GENERATED ALWAYS AS (NULLIF(BTRIM(data ->> '#{key}'), '')) STORED
        SQL
      end
      execute "ALTER TABLE #{table} ADD COLUMN status text GENERATED ALWAYS AS (data ->> 'status') STORED"
      # Bills and payment details keep a workflow state in `status` -- "Final
      # Approved", "Pending at ...", "Paid" -- not an active/inactive flag, and
      # the app never runs active_module_record? over them. Reading status as
      # that flag would mark every bill inactive and hide all 110 of them, so
      # for those two only the delete flags decide.
      active_sql = if config[:workflow_status]
        ModuleMirrorSql::ACTIVE_FROM_DELETE_FLAGS
      else
        ModuleMirrorSql::ACTIVE_FROM_DATA
      end
      execute <<~SQL.squish
        ALTER TABLE #{table}
        ADD COLUMN active boolean GENERATED ALWAYS AS (#{active_sql}) STORED
      SQL

      add_index table, :active
      add_index table, :created_at
      config[:indexes].each { |columns| add_index table, columns }
      config[:columns].each_key do |column|
        execute "CREATE INDEX index_#{table}_on_normalized_#{column} ON #{table} (LOWER(BTRIM(#{column})))"
      end

      execute <<~SQL.squish
        INSERT INTO #{table} (id, data, created_at, updated_at)
        SELECT m.id,
          CASE WHEN jsonb_typeof(m.data::jsonb) = 'object' THEN m.data::jsonb ELSE '{}'::jsonb END,
          m.created_at, m.updated_at
        FROM module_records m
        WHERE m.module_slug = #{connection.quote(config[:slug])}
      SQL

      execute <<~SQL.squish
        SELECT setval(pg_get_serial_sequence('#{table}', 'id'),
          GREATEST((SELECT COALESCE(MAX(id), 0) FROM #{table}), 1))
      SQL
    end

    rewrite_slug_table_function(all_slug_tables)
  end

  def down
    rewrite_slug_table_function(previous_slug_tables)
    TABLES.each_key { |table| drop_table table }
  end

  private

  def previous_slug_tables
    SyncModuleMasterTables::TABLES.merge(
      CreateActivityAndAccessTables::TABLES.to_h { |table, config| [config[:slug], table] }
    )
  end

  def all_slug_tables
    previous_slug_tables.merge(TABLES.to_h { |table, config| [config[:slug], table] })
  end

  def rewrite_slug_table_function(mapping)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_module_master_table(slug text) RETURNS text AS $$
      BEGIN
        RETURN CASE slug
          #{mapping.map { |slug, table| "WHEN '#{slug}' THEN '#{table}'" }.join("\n          ")}
          ELSE NULL
        END;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    SQL
  end
end
