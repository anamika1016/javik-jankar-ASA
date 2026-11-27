require "digest"
require "securerandom"

class ActivateDedicatedModuleStorage < ActiveRecord::Migration[8.1]
  # The archive stays live while its contents are copied.  Each DDL step is
  # committed so the one-way archive-to-dedicated bridge is visible before the
  # backfill begins; only the final sequence/check/view switch takes a short
  # writer lock.
  disable_ddl_transaction!
  EXISTING = {
    "state-master" => "lg_states",
    "district-master" => "lg_districts",
    "block-master" => "lg_blocks",
    "gram-panchayat-master" => "lg_gram_panchayats",
    "village-master" => "lg_villages",
    "lg-directory-list" => "lg_villages",
    "month-master" => "module_months",
    "stakeholder-master" => "module_stakeholders",
    "stakeholder-role" => "module_stakeholder_roles",
    "role-name" => "module_roles",
    "parent-office-add" => "module_parent_offices",
    "office-category-add" => "module_office_categories",
    "office-mapping-add" => "module_sub_offices",
    "project-master" => "module_projects",
    "add-activity-group" => "module_main_activities",
    "add-vrp-activity" => "module_sub_activities",
    "jeevika-jankar-transfer" => "module_jj_transfers",
    "user-hierarchy-mapping" => "module_user_hierarchies",
    "access-control" => "module_access_controls",
    "add-vrp-type" => "module_vrp_types",
    "approval-master" => "module_approvals",
    "training-form" => "module_trainings",
    "other-target" => "module_other_targets",
    "other-target-with-farmer" => "module_other_farmer_targets",
    "jeevika-jankar-bill-process" => "module_bills",
    "jeevika-jankar-payment-detail" => "module_payment_details"
} .freeze
  SLUGS = %w[
    access-control access-control-list activity-group-list activity-master add-activity-group
    add-farmer-form add-vrp-activity add-vrp-type all-user approval-list
    approval-master approval-status-summary bank-master block-master district-master
    gram-panchayat-master ics-master jeevika-jankar-bill-approval-history jeevika-jankar-bill-list jeevika-jankar-bill-process
    jeevika-jankar-completed-payment-list jeevika-jankar-observation-list jeevika-jankar-payment-detail jeevika-jankar-payment-list jeevika-jankar-payment-list-detail
    jeevika-jankar-transfer jeevika-jankar-transfer-list lg-directory-import-status lg-directory-list month-master
    monthly-bill-summary new-user office-category-add office-list office-mapping-add
    other-target other-target-list other-target-with-farmer other-target-with-farmer-list papl360-target
    papl360-target-list parent-office-add payment-status-report person-type position-type
    project-master role-management role-name seed-distribution-target seed-distribution-target-list
    stakeholder-master stakeholder-profile stakeholder-role state-master task-completion-indicator
    task-completion-indicator-list task-indicator-master training-form training-form-edit-request training-form-list
    training-topic-mapping user-hierarchy-list user-hierarchy-mapping user-management-role village-master
    vrp-active-status-history vrp-activity-list vrp-approval-history vrp-bill-add vrp-bill-list
    vrp-registration-list weekly-activity-progress weekly-progress-report weekly-target-add weekly-target-list
  ].freeze
  LG_COLUMNS = {
    'state_name' => %w[state_name state], 'state_code' => %w[state_code],
    'district_name' => %w[district_name district], 'district_code' => %w[district_code],
    'sub_district_name' => %w[sub_district_name sub_district], 'sub_district_code' => %w[sub_district_code],
    'block_name' => %w[block_name cd_block_name block], 'block_code' => %w[block_code cd_block_code],
    'gram_panchayat_name' => %w[gram_panchayat_name gram_panchayat], 'gp_code' => %w[gp_code],
    'village_name' => %w[village_name village], 'village_code' => %w[village_code]
  }.freeze
  ACTIVE = <<~SQL.squish.freeze
    NOT (COALESCE(LOWER(BTRIM(data ->> 'deleted')), '') IN ('1','true','yes','deleted')
      OR COALESCE(LOWER(BTRIM(data ->> 'is_deleted')), '') IN ('1','true','yes','deleted')
      OR COALESCE(LOWER(BTRIM(data ->> 'discarded')), '') IN ('1','true','yes','deleted')
      OR (COALESCE(BTRIM(data ->> 'status'), '') <> '' AND LOWER(BTRIM(data ->> 'status')) <> 'active'))
  SQL

  def up
    create_table :module_entry_identities, id: :bigint, default: nil, if_not_exists: true do |t|
      t.string :module_slug, null: false
    end
    add_index :module_entry_identities, :module_slug, if_not_exists: true
    discovered = select_values("SELECT DISTINCT module_slug FROM module_records")
    mapping = (SLUGS + discovered).uniq.sort.to_h do |slug|
      # Production-only slugs are copied too, never silently left in the archive.
      named = {
        'jeevika-jankar-bill-approval-history' => 'module_bill_approval_histories',
        'vrp-approval-history' => 'module_vrp_approval_histories',
        'training-form-edit-request' => 'module_training_edit_requests',
        'seed-distribution-target' => 'module_seed_distribution_targets',
        'training-topic-mapping' => 'module_training_topic_mappings',
        'person-type' => 'module_person_types', 'role-management' => 'module_role_managements',
        'user-management-role' => 'module_user_management_roles', 'add-farmer-form' => 'module_farmer_forms'
      }
      table = EXISTING[slug] || named[slug] || "module_#{slug.tr('-', '_')[0, 34]}_#{Digest::SHA256.hexdigest(slug)[0, 8]}"
      [slug, table]
    end
    # Routing is schema metadata, so a schema-only SQL restore must retain it.
    routes = mapping.map { |slug, table| "(#{connection.quote(slug)}::text, #{connection.quote(table)}::text)" }.join(', ')
    execute "CREATE OR REPLACE VIEW module_entry_sources AS SELECT * FROM (VALUES #{routes}) AS sources(slug, table_name)"
    mapping.each do |slug, table|
      unless table_exists?(table)
        create_table table, id: :bigint, default: nil do |t|
          t.string :source_slug, null: false, default: slug
          t.jsonb :data, null: false, default: {}
          t.timestamps
        end
        execute "ALTER TABLE #{quote_table_name(table)} ADD COLUMN status text GENERATED ALWAYS AS (data ->> 'status') STORED"
        execute "ALTER TABLE #{quote_table_name(table)} ADD COLUMN active boolean GENERATED ALWAYS AS (#{ACTIVE}) STORED"
      end
      unless column_exists?(table, :source_slug)
        add_column table, :source_slug, :string, default: slug, null: false
      end
      add_column table, :payload_text, :text unless column_exists?(table, :payload_text)
      unless column_exists?(table, :catalogue_active)
        execute "ALTER TABLE #{quote_table_name(table)} ADD COLUMN catalogue_active boolean GENERATED ALWAYS AS (#{ACTIVE}) STORED"
      end
      add_index table, :created_at, if_not_exists: true
      add_index table, :updated_at, if_not_exists: true
    end
    tables = mapping.values.uniq

    # Make the dedicated destinations authoritative for every archive write
    # before copying existing rows.  A live save that happens during backfill
    # is therefore mirrored immediately rather than being lost or requiring a
    # long lock on module_records.
    install_functions
    tables.each { |table| install_table_triggers(table) }
    execute "DROP TRIGGER IF EXISTS zz_module_entries_legacy_bridge ON module_records"
    execute <<~SQL
      CREATE TRIGGER zz_module_entries_legacy_bridge AFTER INSERT OR UPDATE OR DELETE ON module_records
      FOR EACH ROW EXECUTE FUNCTION jj_module_entries_legacy_bridge();
    SQL

    mapping.each do |slug, table|
      # Raw JSON text preserves scalar payloads, key ordering and legacy aliases.
      extra_columns = table.start_with?('lg_') ? ", active, status, #{LG_COLUMNS.keys.join(', ')}" : ''
      payload = "CASE WHEN jsonb_typeof(m.data::jsonb) = 'object' THEN m.data::jsonb ELSE '{}'::jsonb END"
      extra_values = if table.start_with?('lg_')
        expressions = LG_COLUMNS.values.map { |aliases| "COALESCE(#{aliases.map { |key| "NULLIF((#{payload}) ->> '#{key}', '')" }.join(', ')})" }
        ", #{ACTIVE.gsub('data ->>', "(#{payload}) ->>")}, (#{payload})->>'status', #{expressions.join(', ')}"
      else
        ''
      end
      execute <<~SQL
        INSERT INTO #{quote_table_name(table)} (id, source_slug, data, payload_text, created_at, updated_at#{extra_columns})
        SELECT m.id, m.module_slug, #{payload}, m.data, m.created_at, m.updated_at#{extra_values}
        FROM module_records m WHERE m.module_slug = #{connection.quote(slug)}
        -- The legacy bridge is already live. A conflict means a concurrent
        -- legacy write reached the dedicated row after this backfill snapshot;
        -- keep that newer bridged row instead of overwriting it with stale data.
        ON CONFLICT (id) DO NOTHING
      SQL
    end
    tables.each do |table|
      execute "UPDATE #{quote_table_name(table)} SET payload_text = data::text WHERE payload_text IS NULL"
    end

    # All slow work above runs without an archive writer lock. The bridge has
    # kept rows current. Publish the writable view in one short transaction;
    # if a busy writer prevents that lock within three seconds, the migration
    # stops rather than making live saves wait. Its committed preparation is
    # retry-safe, so the next deploy attempt resumes without data loss.
    transaction do
      execute "SET LOCAL lock_timeout = '3s'"
      execute "LOCK TABLE module_records IN SHARE ROW EXCLUSIVE MODE"
      source_count = select_value("SELECT COUNT(*) FROM module_records").to_i
      actual_count = select_value("SELECT COUNT(*) FROM module_entry_identities").to_i
      raise "Dedicated storage contains unexpected extra/missing IDs; archive retained and cutover must not be deployed" unless source_count == actual_count
      execute "CREATE SEQUENCE IF NOT EXISTS module_entry_id_seq AS bigint"
      execute "SELECT setval('module_entry_id_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM module_entry_identities), (SELECT last_value FROM module_records_id_seq), 1))"
      # Old application workers and the new storage allocate from the same sequence.
      # The new sequence is independent of the archive table's lifetime.
      execute "ALTER TABLE module_records ALTER COLUMN id SET DEFAULT nextval('module_entry_id_seq')"
      tables.each { |table| execute "ALTER TABLE #{quote_table_name(table)} ALTER COLUMN id SET DEFAULT nextval('module_entry_id_seq')" }
      create_views(mapping)
      execute "DROP TRIGGER IF EXISTS module_entries_write ON module_entries"
      execute <<~SQL
        CREATE TRIGGER module_entries_write INSTEAD OF INSERT OR UPDATE OR DELETE ON module_entries
        FOR EACH ROW EXECUTE FUNCTION jj_module_entries_write();
      SQL
      execute "UPDATE module_record_read_versions SET revision = #{SecureRandom.random_number(2**62)} WHERE source_key = 'epoch'"
      tables.each do |table|
        execute <<~SQL
          INSERT INTO module_record_read_versions(source_key, revision)
          SELECT 'module:' || source_slug, nextval('module_record_read_version_seq') FROM (SELECT DISTINCT source_slug FROM #{quote_table_name(table)}) sources
          ON CONFLICT (source_key) DO UPDATE SET revision = EXCLUDED.revision
        SQL
      end
      %w[afls vrps users target_mappings].each do |table|
        execute "DROP TRIGGER IF EXISTS jj_module_entry_dependency_changed ON #{quote_table_name(table)}"
        execute <<~SQL
          INSERT INTO module_record_read_versions VALUES ('table:#{table}', nextval('module_record_read_version_seq'))
          ON CONFLICT (source_key) DO UPDATE SET revision = EXCLUDED.revision;
          CREATE TRIGGER jj_module_entry_dependency_changed AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON #{table}
          FOR EACH STATEMENT EXECUTE FUNCTION jj_module_entry_dependency_changed();
        SQL
      end
    end
  end

  def down
    # New writes must not be lost by rolling an archive back over live tables.
    raise ActiveRecord::IrreversibleMigration, 'Dedicated storage now owns writes; retain both stores and roll application code forward'
  end

  private

  def create_views(mapping)
    legs = mapping.group_by(&:last).map do |table, entries|
      slug = entries.size == 1 ? "#{connection.quote(entries.first.first)}::text" : 'source_slug::text'
      "SELECT id, #{slug} AS module_slug, payload_text AS data, created_at, updated_at, xmin::text AS xmin, ctid::text AS ctid FROM #{quote_table_name(table)}"
    end
    native = mapping.group_by(&:last).map do |table, entries|
      slug = entries.size == 1 ? "#{connection.quote(entries.first.first)}::text" : 'source_slug::text'
      "SELECT id, #{slug} AS module_slug, data, created_at, updated_at, catalogue_active, active AS record_active FROM #{quote_table_name(table)}"
    end
    execute "CREATE OR REPLACE VIEW module_entries AS #{legs.join(' UNION ALL ')}"
    execute "ALTER VIEW module_entries ALTER COLUMN id SET DEFAULT nextval('module_entry_id_seq')"
    execute "CREATE OR REPLACE VIEW module_entry_payloads AS #{native.join(' UNION ALL ')}"
  end

  def install_table_triggers(table)
    %w[
      jj_module_entry_prepare
      jj_module_entry_identity_delete
      jj_module_entries_versions_insert
      jj_module_entries_versions_update
      jj_module_entries_versions_delete
      jj_module_entries_versions_truncate
    ].each do |trigger|
      execute "DROP TRIGGER IF EXISTS #{trigger} ON #{quote_table_name(table)}"
    end
    execute <<~SQL
      CREATE TRIGGER jj_module_entry_prepare BEFORE INSERT OR UPDATE ON #{quote_table_name(table)}
      FOR EACH ROW EXECUTE FUNCTION jj_module_entry_prepare();
      CREATE TRIGGER jj_module_entry_identity_delete AFTER DELETE ON #{quote_table_name(table)}
      FOR EACH ROW EXECUTE FUNCTION jj_module_entry_identity_delete();
    SQL
    { 'insert' => 'NEW TABLE AS new_rows', 'update' => 'OLD TABLE AS old_rows NEW TABLE AS new_rows', 'delete' => 'OLD TABLE AS old_rows' }.each do |event, transition|
      execute <<~SQL
        CREATE TRIGGER jj_module_entries_versions_#{event} AFTER #{event.upcase} ON #{quote_table_name(table)}
        REFERENCING #{transition} FOR EACH STATEMENT EXECUTE FUNCTION jj_module_entries_versions_#{event}();
      SQL
    end
    execute <<~SQL
      CREATE TRIGGER jj_module_entries_versions_truncate AFTER TRUNCATE ON #{quote_table_name(table)}
      FOR EACH STATEMENT EXECUTE FUNCTION jj_module_entries_versions_truncate();
    SQL
  end

  def install_functions
    execute <<~SQL
      CREATE FUNCTION jj_module_entry_ensure_epoch() RETURNS void LANGUAGE plpgsql AS $$
      BEGIN
        INSERT INTO module_record_read_versions(source_key, revision)
        VALUES ('epoch', ('x' || substr(md5(random()::text || clock_timestamp()::text), 1, 15))::bit(60)::bigint)
        ON CONFLICT(source_key) DO NOTHING;
      END;
      $$;
      CREATE FUNCTION jj_module_entry_prepare() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE payload jsonb;
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM module_entry_sources WHERE slug = NEW.source_slug AND table_name = TG_TABLE_NAME) THEN
          RAISE EXCEPTION 'Invalid dedicated module source % for %', NEW.source_slug, TG_TABLE_NAME USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'UPDATE' THEN
          IF NEW.id IS DISTINCT FROM OLD.id OR NEW.source_slug IS DISTINCT FROM OLD.source_slug THEN
            DELETE FROM module_entry_identities WHERE id = OLD.id AND module_slug = OLD.source_slug;
          END IF;
          IF NEW.payload_text IS DISTINCT FROM OLD.payload_text THEN
            payload := NEW.payload_text::jsonb;
            NEW.data := CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END;
          ELSIF NEW.data IS DISTINCT FROM OLD.data THEN
            NEW.payload_text := NEW.data::text;
          END IF;
        ELSIF NEW.payload_text IS NULL THEN
          NEW.payload_text := NEW.data::text;
        ELSE
          payload := NEW.payload_text::jsonb;
          NEW.data := CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END;
        END IF;
        INSERT INTO module_entry_identities(id, module_slug) VALUES (NEW.id, NEW.source_slug)
        ON CONFLICT (id) DO UPDATE SET module_slug = EXCLUDED.module_slug
          WHERE module_entry_identities.module_slug = EXCLUDED.module_slug;
        IF NOT FOUND THEN RAISE EXCEPTION 'Duplicate module ID %', NEW.id USING ERRCODE = '23505'; END IF;
        IF TG_TABLE_NAME LIKE 'lg_%' THEN
          payload := NEW.data;
          NEW.status := payload ->> 'status';
          NEW.active := #{ACTIVE.gsub('data ->>', 'payload ->>')};
          #{LG_COLUMNS.map { |column, aliases| "NEW.#{column} := COALESCE(#{aliases.map { |key| "NULLIF(payload ->> '#{key}', '')" }.join(', ')});" }.join("\n          ")}
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE FUNCTION jj_module_entry_identity_delete() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        DELETE FROM module_entry_identities WHERE id = OLD.id AND module_slug = OLD.source_slug;
        RETURN NULL;
      END;
      $$;
      CREATE FUNCTION jj_module_entries_write() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE target text; previous_target text; payload jsonb;
      BEGIN
        IF TG_OP <> 'INSERT' THEN
          SELECT table_name INTO previous_target FROM module_entry_sources WHERE slug = OLD.module_slug;
          IF TG_OP = 'DELETE' OR OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id THEN
            EXECUTE format('DELETE FROM %I WHERE id = $1', previous_target) USING OLD.id;
          END IF;
          IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        END IF;
        SELECT table_name INTO target FROM module_entry_sources WHERE slug = NEW.module_slug;
        IF target IS NULL THEN RAISE EXCEPTION 'Module source not configured: %', NEW.module_slug; END IF;
        payload := NEW.data::jsonb;
        IF TG_OP = 'INSERT' THEN
          EXECUTE format('INSERT INTO %I(id, source_slug, data, payload_text, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6)', target)
          USING NEW.id, NEW.module_slug, CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END, NEW.data, NEW.created_at, NEW.updated_at;
        ELSE
          EXECUTE format('INSERT INTO %I(id, source_slug, data, payload_text, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6)
            ON CONFLICT (id) DO UPDATE SET source_slug = EXCLUDED.source_slug, data = EXCLUDED.data,
              payload_text = EXCLUDED.payload_text, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at', target)
          USING NEW.id, NEW.module_slug, CASE WHEN jsonb_typeof(payload) = 'object' THEN payload ELSE '{}'::jsonb END, NEW.data, NEW.created_at, NEW.updated_at;
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE FUNCTION jj_module_entries_legacy_bridge() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE target text;
      BEGIN
        IF TG_OP <> 'INSERT' THEN
          IF TG_OP = 'DELETE' OR OLD.module_slug IS DISTINCT FROM NEW.module_slug OR OLD.id IS DISTINCT FROM NEW.id THEN
            SELECT table_name INTO target FROM module_entry_sources WHERE slug = OLD.module_slug;
            IF target IS NOT NULL THEN EXECUTE format('DELETE FROM %I WHERE id = $1', target) USING OLD.id; END IF;
          END IF;
          IF TG_OP = 'DELETE' THEN RETURN NULL; END IF;
        END IF;
        SELECT table_name INTO target FROM module_entry_sources WHERE slug = NEW.module_slug;
        -- Unknown slugs written by obsolete code must not silently disappear.
        IF target IS NULL THEN RAISE EXCEPTION 'Module source not configured: %', NEW.module_slug; END IF;
        EXECUTE format('INSERT INTO %I(id, source_slug, data, payload_text, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6)
          ON CONFLICT(id) DO UPDATE SET source_slug = EXCLUDED.source_slug, data = EXCLUDED.data, payload_text = EXCLUDED.payload_text,
            created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at', target)
        USING NEW.id, NEW.module_slug, CASE WHEN jsonb_typeof(NEW.data::jsonb) = 'object' THEN NEW.data::jsonb ELSE '{}'::jsonb END,
          NEW.data, NEW.created_at, NEW.updated_at;
        RETURN NULL;
      END;
      $$;
    SQL
    { 'insert' => 'SELECT source_slug FROM new_rows', 'update' => 'SELECT source_slug FROM new_rows UNION SELECT source_slug FROM old_rows', 'delete' => 'SELECT source_slug FROM old_rows' }.each do |event, sources|
      execute <<~SQL
        CREATE FUNCTION jj_module_entries_versions_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          PERFORM jj_module_entry_ensure_epoch();
          INSERT INTO module_record_read_versions(source_key, revision)
          SELECT 'module:' || source_slug, nextval('module_record_read_version_seq')
          FROM (SELECT DISTINCT source_slug FROM (#{sources}) affected WHERE source_slug IS NOT NULL) keys
          ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
          RETURN NULL;
        END;
        $$;
      SQL
    end
    execute <<~SQL
      CREATE FUNCTION jj_module_entries_versions_truncate() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM jj_module_entry_ensure_epoch();
        INSERT INTO module_record_read_versions(source_key, revision)
        SELECT 'module:' || slug, nextval('module_record_read_version_seq') FROM module_entry_sources WHERE table_name = TG_TABLE_NAME
        ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
        DELETE FROM module_entry_identities WHERE module_slug IN (SELECT slug FROM module_entry_sources WHERE table_name = TG_TABLE_NAME);
        RETURN NULL;
      END;
      $$;
      CREATE FUNCTION jj_module_entry_dependency_changed() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM jj_module_entry_ensure_epoch();
        INSERT INTO module_record_read_versions(source_key, revision) VALUES ('table:' || TG_TABLE_NAME, nextval('module_record_read_version_seq'))
        ON CONFLICT(source_key) DO UPDATE SET revision = EXCLUDED.revision;
        RETURN NULL;
      END;
      $$;
    SQL
  end
end
