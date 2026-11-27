class SyncLgDirectoryTables < ActiveRecord::Migration[8.1]
  # Keeps the lg_* tables in step with module_records.
  #
  # module_records stays the source of truth for now, so the existing Add /
  # Edit / Delete / Excel-upload screens and LgDirectoryImporter carry on
  # untouched -- the lg_* tables are a fast read mirror beside them. Nothing
  # that writes today has to change, and dropping these triggers plus the
  # tables puts everything back exactly as it was.
  #
  # This is a database trigger rather than an ActiveRecord callback on purpose:
  # LgDirectoryImporter writes with insert_all!, which bypasses callbacks
  # entirely, and the module screens issue their own bulk updates. A trigger is
  # the only hook every write path goes through, so the mirror cannot drift.

  TABLES = {
    "state-master" => "lg_states",
    "district-master" => "lg_districts",
    "block-master" => "lg_blocks",
    "gram-panchayat-master" => "lg_gram_panchayats",
    "village-master" => "lg_villages",
    "lg-directory-list" => "lg_villages"
  }.freeze

  # Column mapping and the active predicate come from LgDirectoryColumns, the
  # single definition shared with the backfill and LgDirectory#sync!.
  COLUMNS = LgDirectoryColumns::ALIASES

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_lg_directory_sync() RETURNS trigger AS $$
      DECLARE
        target text;
        payload jsonb;
        is_active boolean;
      BEGIN
        IF TG_OP = 'DELETE' THEN
          target := jj_lg_directory_table(OLD.module_slug);
          IF target IS NOT NULL THEN
            EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
          END IF;
          RETURN NULL;
        END IF;

        -- An edit can move a row between slugs; clear the old home first.
        IF TG_OP = 'UPDATE' AND OLD.module_slug IS DISTINCT FROM NEW.module_slug THEN
          target := jj_lg_directory_table(OLD.module_slug);
          IF target IS NOT NULL THEN
            EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id;
          END IF;
        END IF;

        target := jj_lg_directory_table(NEW.module_slug);
        IF target IS NULL THEN
          RETURN NULL;
        END IF;

        payload := CASE WHEN jsonb_typeof(NEW.data::jsonb) = 'object'
                        THEN NEW.data::jsonb ELSE '{}'::jsonb END;

        -- Mirrors active_module_record?: any delete flag set, or a status that
        -- is present and not "Active", means inactive. Blank status is active.
        is_active := #{LgDirectoryColumns::ACTIVE_SQL};

        EXECUTE format(
          'INSERT INTO %I (id, source_slug, active, status, #{COLUMNS.keys.join(", ")}, data, created_at, updated_at)
           VALUES ($1, $2, $3, $4, #{(5..(COLUMNS.size + 4)).map { |i| "$#{i}" }.join(", ")}, $#{COLUMNS.size + 5}, $#{COLUMNS.size + 6}, $#{COLUMNS.size + 7})
           ON CONFLICT (id) DO UPDATE SET
             source_slug = EXCLUDED.source_slug, active = EXCLUDED.active, status = EXCLUDED.status,
             #{COLUMNS.keys.map { |c| "#{c} = EXCLUDED.#{c}" }.join(", ")},
             data = EXCLUDED.data, updated_at = EXCLUDED.updated_at',
          target
        ) USING
          NEW.id, NEW.module_slug, is_active, payload ->> 'status',
          #{COLUMNS.values.map { |aliases| "COALESCE(#{aliases.map { |k| "NULLIF(payload ->> '#{k}', '')" }.join(', ')})" }.join(",\n          ")},
          payload, NEW.created_at, NEW.updated_at;

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_lg_directory_table(slug text) RETURNS text AS $$
      BEGIN
        RETURN CASE slug
          #{TABLES.map { |slug, table| "WHEN '#{slug}' THEN '#{table}'" }.join("\n          ")}
          ELSE NULL
        END;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    SQL

    execute <<~SQL
      CREATE TRIGGER jj_lg_directory_sync_write
      AFTER INSERT OR UPDATE ON module_records
      FOR EACH ROW EXECUTE FUNCTION jj_lg_directory_sync();
    SQL

    execute <<~SQL
      CREATE TRIGGER jj_lg_directory_sync_delete
      AFTER DELETE ON module_records
      FOR EACH ROW EXECUTE FUNCTION jj_lg_directory_sync();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS jj_lg_directory_sync_write ON module_records"
    execute "DROP TRIGGER IF EXISTS jj_lg_directory_sync_delete ON module_records"
    execute "DROP FUNCTION IF EXISTS jj_lg_directory_sync()"
    execute "DROP FUNCTION IF EXISTS jj_lg_directory_table(text)"
  end
end
