require "securerandom"

# Statement triggers also observe imports/update_all/delete_all, not only Rails
# callbacks. Sequence stamps are never reused after a transaction rolls back.
class AddModuleRecordReadVersions < ActiveRecord::Migration[8.1]
  def up
    execute "LOCK TABLE module_records IN SHARE ROW EXCLUSIVE MODE"
    create_table :module_record_read_versions, id: false do |t|
      t.string :source_key, null: false, primary_key: true
      t.bigint :revision, null: false
    end
    execute "CREATE SEQUENCE module_record_read_version_seq AS bigint"
    execute "INSERT INTO module_record_read_versions VALUES ('epoch', #{SecureRandom.random_number(2**62)})"
    execute <<~SQL
      INSERT INTO module_record_read_versions (source_key, revision)
      SELECT 'module:' || module_slug, nextval('module_record_read_version_seq')
      FROM (SELECT DISTINCT module_slug FROM module_records WHERE module_slug IS NOT NULL) AS sources
    SQL
    {
      "insert" => "SELECT module_slug FROM new_rows",
      "update" => "SELECT module_slug FROM new_rows UNION SELECT module_slug FROM old_rows",
      "delete" => "SELECT module_slug FROM old_rows"
    }.each do |event, sources|
      execute <<~SQL
        CREATE FUNCTION jj_module_record_versions_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          INSERT INTO module_record_read_versions (source_key, revision)
          SELECT source_key, nextval('module_record_read_version_seq') FROM (
            SELECT DISTINCT 'module:' || module_slug AS source_key
            FROM (#{sources}) AS affected WHERE module_slug IS NOT NULL
          ) AS keys ORDER BY source_key
          ON CONFLICT (source_key) DO UPDATE SET revision = EXCLUDED.revision;
          RETURN NULL;
        END;
        $$;
      SQL
      transition = case event
      when "insert" then "NEW TABLE AS new_rows"
      when "update" then "OLD TABLE AS old_rows NEW TABLE AS new_rows"
      else "OLD TABLE AS old_rows"
      end
      execute <<~SQL
        CREATE TRIGGER jj_module_record_versions_#{event} AFTER #{event.upcase} ON module_records
        REFERENCING #{transition} FOR EACH STATEMENT EXECUTE FUNCTION jj_module_record_versions_#{event}()
      SQL
    end
    execute <<~SQL
      CREATE FUNCTION jj_module_record_versions_truncate() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE module_record_read_versions SET revision = nextval('module_record_read_version_seq')
        WHERE source_key <> 'epoch';
        RETURN NULL;
      END;
      $$;
      CREATE TRIGGER jj_module_record_versions_truncate AFTER TRUNCATE ON module_records
      FOR EACH STATEMENT EXECUTE FUNCTION jj_module_record_versions_truncate();
    SQL
  end

  def down
    %w[insert update delete truncate].each do |event|
      execute "DROP TRIGGER IF EXISTS jj_module_record_versions_#{event} ON module_records"
      execute "DROP FUNCTION IF EXISTS jj_module_record_versions_#{event}()"
    end
    drop_table :module_record_read_versions
    execute "DROP SEQUENCE IF EXISTS module_record_read_version_seq"
  end
end
