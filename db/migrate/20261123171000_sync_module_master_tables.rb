class SyncModuleMasterTables < ActiveRecord::Migration[8.1]
  # Keeps the module_* master tables in step with module_records, the same way
  # jj_lg_directory_sync does for the LG Directory tables.
  #
  # This one is far shorter, because those tables derive their named columns
  # with generated columns: the trigger only has to carry the payload across,
  # and PostgreSQL recomputes everything else. There is no column mapping here
  # that could fall out of step with the table definition.

  TABLES = {
    "month-master" => "module_months",
    "stakeholder-master" => "module_stakeholders",
    "stakeholder-role" => "module_stakeholder_roles",
    "role-name" => "module_roles",
    "parent-office-add" => "module_parent_offices",
    "office-category-add" => "module_office_categories",
    "office-mapping-add" => "module_sub_offices"
  }.freeze

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_module_master_table(slug text) RETURNS text AS $$
      BEGIN
        RETURN CASE slug
          #{TABLES.map { |slug, table| "WHEN '#{slug}' THEN '#{table}'" }.join("\n          ")}
          ELSE NULL
        END;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_module_master_sync() RETURNS trigger AS $$
      DECLARE
        target text;
      BEGIN
        IF TG_OP = 'DELETE' THEN
          target := jj_module_master_table(OLD.module_slug);
          IF target IS NOT NULL THEN
            EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
          END IF;
          RETURN NULL;
        END IF;

        -- An edit can move a row to a different master; clear the old one.
        IF TG_OP = 'UPDATE' AND OLD.module_slug IS DISTINCT FROM NEW.module_slug THEN
          target := jj_module_master_table(OLD.module_slug);
          IF target IS NOT NULL THEN
            EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
          END IF;
        END IF;

        target := jj_module_master_table(NEW.module_slug);
        IF target IS NULL THEN
          RETURN NULL;
        END IF;

        EXECUTE format(
          'INSERT INTO %I (id, data, created_at, updated_at) VALUES ($1, $2, $3, $4)
           ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = EXCLUDED.updated_at',
          target
        ) USING
          NEW.id,
          CASE WHEN jsonb_typeof(NEW.data::jsonb) = 'object' THEN NEW.data::jsonb ELSE '{}'::jsonb END,
          NEW.created_at, NEW.updated_at;

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER jj_module_master_sync_write
      AFTER INSERT OR UPDATE ON module_records
      FOR EACH ROW EXECUTE FUNCTION jj_module_master_sync();
    SQL

    execute <<~SQL
      CREATE TRIGGER jj_module_master_sync_delete
      AFTER DELETE ON module_records
      FOR EACH ROW EXECUTE FUNCTION jj_module_master_sync();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS jj_module_master_sync_write ON module_records"
    execute "DROP TRIGGER IF EXISTS jj_module_master_sync_delete ON module_records"
    execute "DROP FUNCTION IF EXISTS jj_module_master_sync()"
    execute "DROP FUNCTION IF EXISTS jj_module_master_table(text)"
  end
end
