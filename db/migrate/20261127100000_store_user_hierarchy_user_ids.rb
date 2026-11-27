require "json"

class StoreUserHierarchyUserIds < ActiveRecord::Migration[8.1]
  def up
    backfill_user_ids!

    %i[level_1_user level_2_user level_3_user].each do |column|
      remove_index :module_user_hierarchies, name: "index_module_user_hierarchies_on_#{column}", if_exists: true
      remove_index :module_user_hierarchies, name: "index_module_user_hierarchies_on_normalized_#{column}", if_exists: true
      remove_column :module_user_hierarchies, column, if_exists: true
    end

    add_column :module_user_hierarchies, :level_1_user_id, :bigint,
      as: "NULLIF(BTRIM(data ->> 'level_1_user_id'), '')::bigint", stored: true
    add_column :module_user_hierarchies, :level_2_user_id, :bigint,
      as: "NULLIF(BTRIM(data ->> 'level_2_user_id'), '')::bigint", stored: true
    add_column :module_user_hierarchies, :level_3_user_id, :bigint,
      as: "NULLIF(BTRIM(data ->> 'level_3_user_id'), '')::bigint", stored: true
    add_column :module_user_hierarchies, :level_2_user_ids, :jsonb,
      as: "COALESCE(data -> 'level_2_user_ids', '[]'::jsonb)", stored: true
    add_column :module_user_hierarchies, :level_3_user_ids, :jsonb,
      as: "COALESCE(data -> 'level_3_user_ids', '[]'::jsonb)", stored: true

    add_index :module_user_hierarchies, :level_1_user_id
    add_index :module_user_hierarchies, :level_2_user_id
    add_index :module_user_hierarchies, :level_3_user_id
    add_index :module_user_hierarchies, :level_2_user_ids, using: :gin
    add_index :module_user_hierarchies, :level_3_user_ids, using: :gin
  end

  def down
    remove_index :module_user_hierarchies, :level_1_user_id, if_exists: true
    remove_index :module_user_hierarchies, :level_2_user_id, if_exists: true
    remove_index :module_user_hierarchies, :level_3_user_id, if_exists: true
    remove_index :module_user_hierarchies, :level_2_user_ids, if_exists: true
    remove_index :module_user_hierarchies, :level_3_user_ids, if_exists: true
    %i[level_1_user_id level_2_user_id level_3_user_id level_2_user_ids level_3_user_ids].each do |column|
      remove_column :module_user_hierarchies, column, if_exists: true
    end

    %i[level_1_user level_2_user level_3_user].each do |column|
      add_column :module_user_hierarchies, column, :text,
        as: "NULLIF(BTRIM(data ->> '#{column}'), '')", stored: true
      expression = column == :level_1_user ? "LOWER(BTRIM(#{column}))" : "LOWER(BTRIM(#{column}))"
      execute "CREATE INDEX index_module_user_hierarchies_on_normalized_#{column} ON module_user_hierarchies (#{expression})"
    end
    add_index :module_user_hierarchies, :level_1_user
  end

  private

  def backfill_user_ids!
    lookup = {}
    if table_exists?(:users)
      select_all("SELECT id, first_name, last_name, user_name, role FROM users").each do |row|
        full_name = [row["first_name"], row["last_name"]].compact_blank.join(" ").presence || row["user_name"].to_s
        add_lookup_labels(lookup, row["id"], "User", full_name, row["user_name"], row["role"])
      end
    end

    if data_source_exists?(:module_entries)
      select_all("SELECT id, data FROM module_entries WHERE module_slug = 'new-user'").each do |row|
        data = row["data"].is_a?(String) ? (JSON.parse(row["data"]) rescue {}) : row["data"]
        next unless data.is_a?(Hash)
        full_name = [data["first_name"], data["last_name"]].compact_blank.join(" ").presence || data["user_name"].to_s
        add_lookup_labels(lookup, row["id"], "ModuleRecord", full_name, data["user_name"], data["role"])
      end
    end

    select_all("SELECT id, data FROM module_user_hierarchies").each do |row|
      data = row["data"].is_a?(String) ? (JSON.parse(row["data"]) rescue {}) : row["data"]
      next unless data.is_a?(Hash)

      write_user_ref(data, "level_1_user", lookup)
      mappings = data["level_2_mappings"]
      mappings = mappings.values if mappings.is_a?(Hash)
      if mappings.blank?
        level_2_labels = Array(data["level_2_users"].presence || data["level_2_user"])
          .flat_map { |value| value.to_s.split(/[;,]/) }.map(&:strip).reject(&:blank?)
        mappings = level_2_labels.map { |label| { "level_2_user" => label, "level_3_users" => [] } }
      end
      mappings = Array(mappings).filter_map do |mapping|
        next unless mapping.is_a?(Hash)

        write_user_ref(mapping, "level_2_user", lookup)
        level_3_labels = Array(mapping["level_3_users"]).flat_map { |value| value.to_s.split(/[;,]/) }.map(&:strip).reject(&:blank?)
        level_3_refs = level_3_labels.filter_map do |label|
          ref = lookup[label.squish.downcase] || lookup[normalize_label(label)]
          ref if ref.is_a?(Hash)
        end
        mapping["level_3_user_ids"] = level_3_refs.map { |ref| ref["id"] }.uniq
        mapping["level_3_user_record_types"] = level_3_refs.map { |ref| ref["record_type"] }.uniq
        mapping
      end

      data["level_2_mappings"] = mappings
      data["level_2_user_ids"] = mappings.filter_map { |mapping| mapping["level_2_user_id"] }.uniq
      data["level_2_user_record_types"] = mappings.filter_map { |mapping| mapping["level_2_user_record_type"] }.uniq
      data["level_3_user_ids"] = mappings.flat_map { |mapping| Array(mapping["level_3_user_ids"]) }.uniq
      data["level_3_user_record_types"] = mappings.flat_map { |mapping| Array(mapping["level_3_user_record_types"]) }.uniq
      data["level_2_user_id"] = data["level_2_user_ids"].first
      data["level_3_user_id"] = data["level_3_user_ids"].first
      execute "UPDATE module_user_hierarchies SET data = #{connection.quote(data.to_json)}::jsonb WHERE id = #{connection.quote(row['id'])}"
    end
  end

  def write_user_ref(data, key, lookup)
    id_key = "#{key}_id"
    type_key = "#{key}_record_type"
    label = data[key].to_s
    ref = lookup[label.squish.downcase] || lookup[normalize_label(label)]
    return unless ref.is_a?(Hash)

    data[id_key] = ref["id"]
    data[type_key] = ref["record_type"]
  end

  def add_lookup_labels(lookup, id, record_type, name, username, role)
    return if name.blank? && username.blank?

    labels = [name, username].compact_blank
    labels += labels.map { |label| "#{label} (#{role})" } if role.present?
    labels.each do |label|
      ref = { "id" => id.to_i, "record_type" => record_type }
      add_lookup_key(lookup, label.to_s.squish.downcase, ref)
      add_lookup_key(lookup, normalize_label(label), ref)
    end
  end

  def add_lookup_key(lookup, key, ref)
    return if key.blank?

    if lookup.key?(key) && lookup[key] != ref
      lookup[key] = :ambiguous
    else
      lookup[key] ||= ref
    end
  end

  def normalize_label(value)
    value.to_s.sub(/\s*\([^)]*\)\s*\z/, "").squish.downcase
  end
end
