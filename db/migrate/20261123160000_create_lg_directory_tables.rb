class CreateLgDirectoryTables < ActiveRecord::Migration[8.1]
  # The LG Directory masters (State / District / Block / GP / Village and the
  # combined All List) have lived as rows in module_records, where every read
  # means loading the row, parsing its JSON payload and filtering in Ruby.
  # Building one village dropdown loads 4,153 records and costs ~73ms, and a
  # registration form builds five of them.
  #
  # These tables hold the same rows with the payload's fields lifted into real,
  # indexed columns, so a dropdown becomes an indexed SELECT of two columns.
  #
  # Two things make this safe to adopt without touching stored data:
  #
  #   1. The primary key is COPIED from module_records.id, not regenerated.
  #      vrp_profiles.state_id/district_id/block_id/gram_panchayat_id/village_id
  #      and the vrps.village_ids / gram_panchayat_ids arrays all store those
  #      ids, so preserving them keeps every existing mapping resolving.
  #      (afls.village_id and target_mappings.village_id are NOT these ids --
  #      they come from the ASA directory and run past module_records' max id.)
  #
  #   2. created_at is copied too. The option lists are ordered created_at DESC
  #      and then de-duplicated by label, keeping the first row per label, so
  #      the ordering decides which id represents a repeated name. Same order
  #      in, same ids out.
  #
  # The original `data` payload is kept verbatim alongside the columns, so the
  # existing Add/Edit/Delete/Export screens and every label-derivation rule keep
  # working on exactly the data they see today. Nothing is deleted from
  # module_records here; these tables are a faster read path beside it.

  LEVELS = {
    lg_states: "state-master",
    lg_districts: "district-master",
    lg_blocks: "block-master",
    lg_gram_panchayats: "gram-panchayat-master",
    lg_villages: ["village-master", "lg-directory-list"]
  }.freeze

  # Every level carries its own ancestors in the payload, so one shared column
  # set serves all five and the models stay interchangeable. The payload-to-
  # column mapping lives in LgDirectoryColumns so the trigger and the Ruby
  # resync cannot drift from this backfill.
  HIERARCHY_COLUMNS = LgDirectoryColumns::ALIASES

  def up
    LEVELS.each_key do |table|
      create_table table, id: false do |t|
        # Copied from module_records.id -- see the note above.
        t.primary_key :id, :bigint, default: nil
        t.string :source_slug, null: false
        # Precomputed from the payload's deleted/is_deleted/discarded flags and
        # status, which is the predicate every caller applies in Ruby today.
        t.boolean :active, null: false, default: true
        t.string :status
        HIERARCHY_COLUMNS.each_key { |column| t.string column }
        t.jsonb :data, null: false, default: {}
        t.timestamps
      end

      add_index table, [:active, :source_slug], name: "index_#{table}_on_active_and_source"
      add_index table, :source_slug
      add_index table, :created_at
    end

    # Per-level lookup indexes, on the column that level is named by.
    add_index :lg_states, "LOWER(BTRIM(state_name))", name: "index_lg_states_on_normalized_name"
    add_index :lg_districts, "LOWER(BTRIM(district_name))", name: "index_lg_districts_on_normalized_name"
    add_index :lg_districts, "LOWER(BTRIM(state_name))", name: "index_lg_districts_on_normalized_state"
    add_index :lg_blocks, "LOWER(BTRIM(block_name))", name: "index_lg_blocks_on_normalized_name"
    add_index :lg_blocks, "LOWER(BTRIM(district_name))", name: "index_lg_blocks_on_normalized_district"
    add_index :lg_gram_panchayats, "LOWER(BTRIM(gram_panchayat_name))", name: "index_lg_gps_on_normalized_name"
    add_index :lg_gram_panchayats, "LOWER(BTRIM(block_name))", name: "index_lg_gps_on_normalized_block"
    add_index :lg_villages, "LOWER(BTRIM(village_name))", name: "index_lg_villages_on_normalized_name"
    add_index :lg_villages, "LOWER(BTRIM(block_name))", name: "index_lg_villages_on_normalized_block"
    add_index :lg_villages, "LOWER(BTRIM(gram_panchayat_name))", name: "index_lg_villages_on_normalized_gp"
    add_index :lg_villages, :village_code

    LEVELS.each { |table, slugs| backfill(table, Array(slugs)) }
  end

  def down
    LEVELS.each_key { |table| drop_table table }
  end

  private

  def backfill(table, slugs)
    # NULLIF(..., '') so a blank alias falls through to the next one; the
    # payloads carry empty strings for fields a given master does not use.
    columns = HIERARCHY_COLUMNS.map do |_column, aliases|
      "COALESCE(#{aliases.map { |key| "NULLIF(payload ->> '#{key}', '')" }.join(', ')})"
    end.join(",\n        ")
    quoted_slugs = slugs.map { |slug| connection.quote(slug) }.join(", ")

    execute <<~SQL.squish
      INSERT INTO #{table} (
        id, source_slug, active, status, #{HIERARCHY_COLUMNS.keys.join(", ")}, data, created_at, updated_at
      )
      SELECT
        m.id,
        m.module_slug,
        #{LgDirectoryColumns::ACTIVE_SQL},
        payload ->> 'status',
        #{columns},
        payload,
        m.created_at,
        m.updated_at
      FROM module_records m
      CROSS JOIN LATERAL (
        SELECT CASE WHEN jsonb_typeof(m.data::jsonb) = 'object' THEN m.data::jsonb ELSE '{}'::jsonb END
      ) AS t(payload)
      WHERE m.module_slug IN (#{quoted_slugs})
    SQL

    # The ids came from module_records' sequence, so this one has to start
    # above them or the first insert through the new table collides.
    execute <<~SQL.squish
      SELECT setval(
        pg_get_serial_sequence('#{table}', 'id'),
        GREATEST((SELECT COALESCE(MAX(id), 0) FROM #{table}), 1)
      )
    SQL
  end
end
