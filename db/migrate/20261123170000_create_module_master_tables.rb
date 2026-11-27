class CreateModuleMasterTables < ActiveRecord::Migration[8.1]
  # The remaining small masters, moved out of module_records onto tables of
  # their own so they can be read and joined by id.
  #
  # Be clear about the payoff: these hold 37 rows between them, so unlike the
  # LG Directory tables there is no speed to win here. What they buy is the
  # shape -- typed, indexed columns and a real id to join on -- which is what
  # lets module_records be retired a slug at a time.
  #
  # Each table keeps module_records.id as its primary key, for the same reason
  # the LG tables do: ids already stored elsewhere have to keep resolving.
  #
  # The named columns are PostgreSQL generated columns derived from `data`.
  # That is deliberate: the extraction rule lives in the table definition and
  # nowhere else, so the sync trigger only ever writes the payload and cannot
  # disagree with it -- unlike the LG tables, where the same mapping is spelled
  # out in the backfill, the trigger and the Ruby resync.

  TABLES = {
    "module_months" => {
      slug: "month-master",
      columns: { "month_name" => "month_name", "financial_year" => "financial_year" },
      indexes: [["financial_year", "month_name"]]
    },
    "module_stakeholders" => {
      slug: "stakeholder-master",
      columns: { "stakeholder_name" => "stakeholder_name_in_english",
                 "stakeholder_name_hindi" => "stakeholder_name_in_hindi",
                 "logo_upload" => "logo_upload" },
      indexes: [["stakeholder_name"]]
    },
    "module_stakeholder_roles" => {
      slug: "stakeholder-role",
      columns: { "stakeholder_category" => "stakeholder_category", "stakeholder_role" => "stakeholder_role" },
      indexes: [["stakeholder_category", "stakeholder_role"]]
    },
    "module_roles" => {
      slug: "role-name",
      columns: { "stakeholder_category" => "stakeholder_category",
                 "stakeholder_role" => "stakeholder_role", "role_name" => "role_name" },
      indexes: [["stakeholder_category", "stakeholder_role"], ["role_name"]]
    },
    "module_parent_offices" => {
      slug: "parent-office-add",
      columns: { "stakeholder_category" => "stakeholder_category",
                 "parent_office_type" => "parent_office_type",
                 "parent_office_name" => "parent_office_name",
                 "parent_office" => "parent_office", "office_level" => "office_level" },
      indexes: [["parent_office_name"], ["stakeholder_category", "office_level"]]
    },
    "module_office_categories" => {
      slug: "office-category-add",
      columns: { "stakeholder_category" => "stakeholder_category",
                 "parent_category" => "parent_category",
                 "office_name" => "office_name", "office_level" => "office_level" },
      indexes: [["office_name"], ["parent_category"]]
    },
    "module_sub_offices" => {
      slug: "office-mapping-add",
      columns: { "stakeholder_category" => "stakeholder_category",
                 "parent_category" => "parent_category", "office_name" => "office_name",
                 "sub_office_name" => "sub_office_name", "office_level" => "office_level" },
      # The dashboard's TO filter looks up sub offices by their FCO, so that
      # pair is the one that has to be indexed.
      indexes: [["office_name", "sub_office_name"], ["parent_category"]]
    }
  }.freeze

  def up
    TABLES.each do |table, config|
      create_table table, id: false do |t|
        t.primary_key :id, :bigint, default: nil
        t.jsonb :data, null: false, default: {}
        t.timestamps
      end

      # Derived straight from the payload, so they can never drift from it.
      config[:columns].each do |column, key|
        execute <<~SQL.squish
          ALTER TABLE #{table}
          ADD COLUMN #{column} text
          GENERATED ALWAYS AS (NULLIF(BTRIM(data ->> '#{key}'), '')) STORED
        SQL
      end
      execute <<~SQL.squish
        ALTER TABLE #{table}
        ADD COLUMN status text GENERATED ALWAYS AS (data ->> 'status') STORED
      SQL
      execute <<~SQL.squish
        ALTER TABLE #{table}
        ADD COLUMN active boolean
        GENERATED ALWAYS AS (#{ModuleMirrorSql::ACTIVE_FROM_DATA}) STORED
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
  end

  def down
    TABLES.each_key { |table| drop_table table }
  end
end
