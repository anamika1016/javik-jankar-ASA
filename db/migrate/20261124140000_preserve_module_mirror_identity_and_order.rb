require "securerandom"

class PreserveModuleMirrorIdentityAndOrder < ActiveRecord::Migration[8.1]
  # Existing deployments already ran the mirror migrations. Patch their sync
  # functions forward rather than editing a migration that will not run again.
  FUNCTIONS = %w[jj_lg_directory_sync jj_module_master_sync].freeze
  OLD_MOVE = "IF TG_OP = 'UPDATE' AND OLD.module_slug IS DISTINCT FROM NEW.module_slug THEN".freeze
  NEW_MOVE = "IF TG_OP = 'UPDATE' AND (OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id) THEN".freeze
  OLD_VALUES = "data = EXCLUDED.data, updated_at = EXCLUDED.updated_at".freeze
  NEW_VALUES = "data = EXCLUDED.data, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at".freeze
  TABLES = %w[
    lg_states lg_districts lg_blocks lg_gram_panchayats lg_villages
    module_months module_stakeholders module_stakeholder_roles module_roles
    module_parent_offices module_office_categories module_sub_offices
    module_projects module_main_activities module_sub_activities
    module_jj_transfers module_user_hierarchies module_access_controls
    module_vrp_types module_approvals module_trainings module_other_targets
    module_other_farmer_targets module_bills module_payment_details
  ].freeze

  def up
    # Old create/backfill and trigger installation ran in separate migrations.
    # Reconcile writes made in that gap while source writers are paused; readers
    # remain available. The migrator runs this entire change transactionally.
    execute "LOCK TABLE module_records IN SHARE ROW EXCLUSIVE MODE"
    rewrite_functions(OLD_MOVE => NEW_MOVE, OLD_VALUES => NEW_VALUES)
    reconcile_mirrors
    execute <<~SQL
      CREATE OR REPLACE FUNCTION jj_module_mirrors_truncate() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        TRUNCATE TABLE #{TABLES.join(', ')};
        RETURN NULL;
      END;
      $$;
      DROP TRIGGER IF EXISTS jj_module_mirrors_sync_truncate ON module_records;
      CREATE TRIGGER jj_module_mirrors_sync_truncate
      AFTER TRUNCATE ON module_records
      FOR EACH STATEMENT EXECUTE FUNCTION jj_module_mirrors_truncate();
    SQL
    # Pruning an orphan does not write its already-deleted source row. Retire
    # cached mirror snapshots too, including shared caches across app workers.
    if table_exists?(:module_record_read_versions)
      execute "UPDATE module_record_read_versions SET revision = #{SecureRandom.random_number(2**62)} WHERE source_key = 'epoch'"
    end
  end

  def down
    execute "DROP TRIGGER IF EXISTS jj_module_mirrors_sync_truncate ON module_records"
    execute "DROP FUNCTION IF EXISTS jj_module_mirrors_truncate()"
    rewrite_functions(NEW_MOVE => OLD_MOVE, NEW_VALUES => OLD_VALUES)
  end

  private

  def reconcile_mirrors
    return unless %w[jj_lg_directory_table jj_module_master_table].all? do |function|
      select_value("SELECT to_regprocedure(#{connection.quote("#{function}(text)")})::text")
    end

    legs = TABLES.map do |table|
      slug = table.start_with?("lg_") ? "source_slug" : "NULL::text"
      "SELECT id, #{slug} AS slug, #{connection.quote(table)} AS target, data, created_at, updated_at FROM #{table}"
    end
    # Reuse the installed trigger's complete mapping instead of maintaining a
    # second copy of LG aliases/generated-column rules here. Only missing or
    # stale rows are replayed. Business data and timestamps remain unchanged.
    execute <<~SQL
      WITH mirrors AS MATERIALIZED (#{legs.join(' UNION ALL ')})
      UPDATE module_records AS source SET data = source.data
      WHERE COALESCE(jj_lg_directory_table(source.module_slug), jj_module_master_table(source.module_slug)) IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM mirrors
          WHERE mirrors.id = source.id
            AND mirrors.target = COALESCE(jj_lg_directory_table(source.module_slug), jj_module_master_table(source.module_slug))
            AND (mirrors.slug IS NULL OR mirrors.slug = source.module_slug)
            AND mirrors.data = CASE WHEN jsonb_typeof(source.data::jsonb) = 'object' THEN source.data::jsonb ELSE '{}'::jsonb END
            AND mirrors.created_at IS NOT DISTINCT FROM source.created_at
            AND mirrors.updated_at IS NOT DISTINCT FROM source.updated_at
        )
    SQL
    TABLES.each do |table|
      execute <<~SQL
        DELETE FROM #{table} AS mirror WHERE NOT EXISTS (
          SELECT 1 FROM module_records AS source WHERE source.id = mirror.id
            AND COALESCE(jj_lg_directory_table(source.module_slug), jj_module_master_table(source.module_slug)) = #{connection.quote(table)}
        )
      SQL
    end
  end

  def rewrite_functions(replacements)
    FUNCTIONS.each do |function|
      # schema.rb restores tables without functions. Such databases keep the
      # legacy read fallback; there is no installed sync function to patch.
      next unless select_value("SELECT to_regprocedure(#{connection.quote("#{function}()")})::text")

      definition = select_value("SELECT pg_get_functiondef(#{connection.quote("#{function}()")}::regprocedure)")
      replacements.each do |before, after|
        unless definition.include?(before) || definition.include?(after)
          raise "Unexpected #{function} definition; refusing to change its sync logic"
        end
        definition = definition.gsub(before, after)
      end
      execute definition
    end
  end
end
