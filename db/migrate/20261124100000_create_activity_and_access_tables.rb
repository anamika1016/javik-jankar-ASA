require Rails.root.join("db/migrate/20261123171000_sync_module_master_tables")

class CreateActivityAndAccessTables < ActiveRecord::Migration[8.1]
  # The activity, transfer, hierarchy and access-control masters, moved out of
  # module_records onto tables of their own, the same way as the earlier batch
  # in CreateModuleMasterTables: module_records.id is kept as the primary key,
  # the payload is kept verbatim in `data`, and the named columns are generated
  # from it so the extraction rule lives in the table definition and nowhere
  # else.
  #
  # Only six tables, not the eleven screens that were asked for. The five
  # "List" screens -- Main/Sub Major Work Indicator List, Jeevika Jankar
  # Transfer List, Cluster Incharge Under Jeevika Jankar User, Access Control
  # List -- are not separate data. modules_controller maps each to the entry
  # slug it lists (activity-group-list -> add-activity-group, and so on), and
  # all five hold zero rows. They start reading these tables the moment their
  # source slug does.
  #
  # As with the last batch, 44 rows between them means there is no speed to win
  # here; the point is the shape -- indexed columns and a real id to join on.

  TABLES = {
    "module_projects" => {
      slug: "project-master",
      columns: { "project_name" => "project_name" },
      indexes: [["project_name"]]
    },
    "module_main_activities" => {
      slug: "add-activity-group",
      columns: { "main_activity_name" => "main_activity_name" },
      indexes: [["main_activity_name"]]
    },
    "module_sub_activities" => {
      slug: "add-vrp-activity",
      columns: { "main_activity" => "main_activity",
                 "sub_activity_name" => "sub_activity_name",
                 "unit" => "unit" },
      # Sub activities are almost always looked up by their parent.
      indexes: [["main_activity", "sub_activity_name"]]
    },
    "module_jj_transfers" => {
      slug: "jeevika-jankar-transfer",
      columns: { "stakeholder_category" => "stakeholder_category",
                 "user_name" => "user_name", "fcoc" => "fcoc",
                 "sidebar_menu" => "sidebar_menu" },
      indexes: [["fcoc"], ["user_name"]]
    },
    "module_user_hierarchies" => {
      slug: "user-hierarchy-mapping",
      columns: { "level_1_user" => "level_1_user",
                 "level_2_user" => "level_2_user",
                 "level_3_user" => "level_3_user" },
      indexes: [["level_1_user"]]
    },
    "module_access_controls" => {
      slug: "access-control",
      columns: { "stakeholder" => "stakeholder",
                 "stakeholder_role" => "stakeholder_role",
                 "role_name" => "role_name", "can_view" => "can_view" },
      indexes: [["stakeholder_role", "role_name"], ["role_name"]]
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
      execute <<~SQL.squish
        ALTER TABLE #{table}
        ADD COLUMN active boolean GENERATED ALWAYS AS (#{ModuleMirrorSql::ACTIVE_FROM_DATA}) STORED
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

    # One slug-to-table function serves the trigger, so adding these six is a
    # matter of extending the mapping rather than writing another trigger.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_module_master_table(slug text) RETURNS text AS $$
      BEGIN
        RETURN CASE slug
          #{(SyncModuleMasterTables::TABLES.merge(TABLES.to_h { |table, config| [config[:slug], table] }))
              .map { |slug, table| "WHEN '#{slug}' THEN '#{table}'" }.join("\n          ")}
          ELSE NULL
        END;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_module_master_table(slug text) RETURNS text AS $$
      BEGIN
        RETURN CASE slug
          #{SyncModuleMasterTables::TABLES.map { |slug, table| "WHEN '#{slug}' THEN '#{table}'" }.join("\n          ")}
          ELSE NULL
        END;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    SQL
    TABLES.each_key { |table| drop_table table }
  end
end
