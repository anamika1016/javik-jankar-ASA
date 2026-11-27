require "json"

class StoreModuleReferenceIds < ActiveRecord::Migration[8.1]
  # Display values stay in `data` so existing screens and reports keep their
  # labels. Relationship columns and the new request payloads use IDs.
  SINGLE_REFERENCES = {
    "module_access_controls" => {
      "stakeholder" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]],
      "stakeholder_role" => ["module_stakeholder_roles", %w[stakeholder_role]],
      "role_name" => ["module_roles", %w[role_name]]
    },
    "module_approvals" => {
      "stakeholder_role" => ["module_stakeholder_roles", %w[stakeholder_role]],
      "role_name" => ["module_roles", %w[role_name]]
    },
    "module_roles" => {
      "stakeholder_category" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]],
      "stakeholder_role" => ["module_stakeholder_roles", %w[stakeholder_role]]
    },
    "module_stakeholder_roles" => {
      "stakeholder_category" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]]
    },
    "module_jj_transfers" => {
      "stakeholder_category" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]],
      "user_name" => ["users", %w[user_name]]
    },
    "module_parent_offices" => {
      "stakeholder_category" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]],
      "parent_office" => ["module_parent_offices", %w[parent_office_name]]
    },
    "module_office_categories" => {
      "stakeholder_category" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]],
      "parent_category" => ["module_parent_offices", %w[parent_office_name]]
    },
    "module_sub_offices" => {
      "stakeholder_category" => ["module_stakeholders", %w[stakeholder_name_in_english stakeholder_name]],
      "parent_category" => ["module_parent_offices", %w[parent_office_name]],
      "office_name" => ["module_office_categories", %w[office_name category_name]]
    },
    "module_sub_activities" => {},
    "module_trainings" => {
      "month" => ["module_months", %w[month_name]]
    },
    "module_other_targets" => {
      "month" => ["module_months", %w[month_name]],
      "ics_name" => ["module_ics_master", %w[ics_name]]
    },
    "module_other_farmer_targets" => {
      "month" => ["module_months", %w[month_name]]
    },
    "module_bills" => {
      "bill_month" => ["module_months", %w[month_name]]
    },
    "module_payment_details" => {
      "bill_month" => ["module_months", %w[month_name]]
    }
  }.freeze

  DIRECT_ID_FIELDS = {
    "module_sub_activities" => %w[main_activity_id],
    "module_trainings" => %w[jeevika_jankar_id],
    "module_other_targets" => %w[jeevika_jankar_id target_mapping_id],
    "module_other_farmer_targets" => %w[jeevika_jankar_id target_mapping_id],
    "module_bills" => %w[select_vrp],
    "module_payment_details" => %w[select_vrp]
  }.freeze

  MULTI_REFERENCES = {
    "module_jj_transfers" => {
      "jeevika_jankar_names" => ["vrps", %w[name user_name mobile_no]]
    },
    "module_trainings" => {
      "main_activity" => ["module_main_activities", %w[main_activity_name activity_group_name]],
      "sub_activity" => ["module_sub_activities", %w[sub_activity_name activity_name vrp_activity_name]]
    }
  }.freeze

  COMPOSITE_REFERENCE_INDEXES = {
    "module_access_controls" => [%w[stakeholder_role_id role_name_id]],
    "module_bills" => [%w[select_vrp bill_month_id]],
    "module_office_categories" => [%w[parent_category_id]],
    "module_parent_offices" => [%w[stakeholder_category_id office_level]],
    "module_roles" => [%w[stakeholder_category_id stakeholder_role_id]],
    "module_stakeholder_roles" => [%w[stakeholder_category_id stakeholder_role]],
    "module_sub_activities" => [%w[main_activity_id sub_activity_name]],
    "module_sub_offices" => [%w[office_name_id sub_office_name]],
    "module_trainings" => [%w[jeevika_jankar_id month_id], %w[month_id training_method]],
    "module_payment_details" => [%w[select_vrp bill_month_id]]
  }.freeze

  def up
    backfill_reference_ids!
    add_target_mapping_reference_ids!

    SINGLE_REFERENCES.each do |table, references|
      references.each_key { |field| replace_text_reference_column(table, field, :bigint) }
    end
    MULTI_REFERENCES.each do |table, references|
      references.each_key { |field| replace_text_reference_column(table, field, :jsonb, multiple: true) }
    end
    DIRECT_ID_FIELDS.each do |table, fields|
      fields.each { |field| replace_text_reference_column(table, field, :bigint) }
    end

    SINGLE_REFERENCES.each do |table, references|
      references.each_key { |field| add_reference_column(table, "#{field}_id", :bigint) }
    end
    MULTI_REFERENCES.each do |table, references|
      references.each_key { |field| add_reference_column(table, "#{field}_ids", :jsonb, multiple: true) }
    end
    DIRECT_ID_FIELDS.each do |table, fields|
      fields.each { |field| add_reference_column(table, field, :bigint, source_key: field, output_field: field) }
    end

    create_reference_indexes
  end

  def down
    remove_reference_indexes
    COMPOSITE_REFERENCE_INDEXES.each do |table, indexes|
      indexes.each { |columns| remove_index table, columns: columns, if_exists: true }
    end
    remove_index :target_mappings, :month_id, if_exists: true
    remove_index :target_mappings, :main_activity_id, if_exists: true
    remove_index :target_mappings, :sub_activity_id, if_exists: true
    %i[month_id main_activity_id sub_activity_id].each do |column|
      remove_column :target_mappings, column, if_exists: true
    end
    (SINGLE_REFERENCES.keys + MULTI_REFERENCES.keys + DIRECT_ID_FIELDS.keys).uniq.each do |table|
      fields = SINGLE_REFERENCES.fetch(table, {}).keys + MULTI_REFERENCES.fetch(table, {}).keys + DIRECT_ID_FIELDS.fetch(table, [])
      fields.uniq.each do |field|
        direct_id_field = DIRECT_ID_FIELDS.fetch(table, []).include?(field)
        remove_column table, "#{field}_id", if_exists: true unless direct_id_field
        remove_column table, "#{field}_ids", if_exists: true unless direct_id_field
        remove_column table, field, if_exists: true if direct_id_field
        next if direct_id_field

        add_column table, field, :text,
          as: "NULLIF(BTRIM(data ->> '#{field}'), '')", stored: true unless column_exists?(table, field)
        add_index table, field unless index_exists?(table, field)
        index_name = "index_#{table}_on_normalized_#{field}"
        execute "CREATE INDEX #{index_name} ON #{table} (LOWER(BTRIM(#{field})))" unless index_exists?(table, name: index_name)
      end
    end
  end

  private

  def backfill_reference_ids!
    @lookups = {}
    backfill_sub_activity_main_ids!
    SINGLE_REFERENCES.each do |table, references|
      references.each do |field, (source_table, source_keys)|
        lookup = lookup_for(source_table, source_keys)
        backfill_field(table, field, lookup)
      end
    end
    MULTI_REFERENCES.each do |table, references|
      references.each do |field, (source_table, source_keys)|
        lookup = lookup_for(source_table, source_keys)
        backfill_field(table, field, lookup, multiple: true)
      end
    end
    # Direct ID payload keys already contain their identifiers.
  end

  def backfill_sub_activity_main_ids!
    return unless data_source_exists?(:module_sub_activities)

    lookup = lookup_for("module_main_activities", %w[main_activity_name activity_group_name])
    select_all("SELECT id, data FROM module_sub_activities").each do |row|
      data = parse_json(row["data"])
      next unless data.is_a?(Hash)

      label = data["main_activity"].to_s.sub(/\A\s*\d+\.\s*/, "").squish
      next if label.blank?

      main_activity_id = lookup[normalize_label(label)]
      next unless main_activity_id.is_a?(Integer)
      next if data["main_activity_id"].to_s == main_activity_id.to_s

      data["main_activity_id"] = main_activity_id
      update_data("module_sub_activities", row["id"], data)
    end
  end

  def lookup_for(table, keys)
    @lookups[[table, keys]] ||= begin
      result = {}
      source_exists = table == "module_ics_master" ? data_source_exists?(:module_records) : data_source_exists?(table)
      return result unless source_exists

      if table == "users"
        select_all("SELECT id, first_name, last_name, user_name FROM users").each do |row|
          labels = [row["user_name"], [row["first_name"], row["last_name"]].compact_blank.join(" ")]
          labels.each do |label|
            add_lookup_key(result, normalize_label(label), row["id"].to_i) if label.present?
          end
        end
      elsif table == "vrps"
        select_all("SELECT id, name, user_name, mobile_no FROM vrps").each do |row|
          display_name = row["name"].presence || row["user_name"].presence
          next if display_name.blank?

          label = [display_name, row["mobile_no"].presence, row["id"]].compact.join(" - ")
          add_lookup_key(result, normalize_label(label), row["id"].to_i)
        end
      elsif table == "module_ics_master"
        select_all("SELECT id, data FROM module_records WHERE module_slug = 'ics-master'").each do |row|
          data = parse_json(row["data"])
          next unless data.is_a?(Hash)

          keys.each do |key|
            label = data[key].to_s.squish
            add_lookup_key(result, normalize_label(label), row["id"].to_i) if label.present?
          end
        end
      else
        select_all("SELECT id, data FROM #{connection.quote_table_name(table)}").each do |row|
          data = parse_json(row["data"])
          next unless data.is_a?(Hash)

          keys.each do |key|
            label = data[key].to_s.squish
            add_lookup_key(result, normalize_label(label), row["id"].to_i) if label.present?
          end
        end
      end
      result
    end
  end

  def backfill_field(table, field, lookup, multiple: false)
    return unless data_source_exists?(table)

    select_all("SELECT id, data FROM #{connection.quote_table_name(table)}").each do |row|
      data = parse_json(row["data"])
      next unless data.is_a?(Hash)
      original_data = data.deep_dup

      labels = Array(data[field]).flat_map { |value| value.to_s.split(/[;,]/) }
        .map { |label| label.sub(/\A\s*\d+\.\s*/, "").squish }.reject(&:blank?)
      ids = labels.filter_map do |label|
        value = lookup[normalize_label(label)]
        value if value.is_a?(Integer)
      end.uniq
      if multiple
        data["#{field}_ids"] = ids
      else
        data["#{field}_id"] = ids.one? ? ids.first : nil
      end
      update_data(table, row["id"], data) if data != original_data
    end
  end

  def replace_text_reference_column(table, field, type, multiple: false)
    return unless data_source_exists?(table)

    connection.indexes(table).each do |index|
      columns = index.columns.to_s.split(",").map(&:strip)
      remove_index table, name: index.name if columns.include?(field) || index.columns.to_s.include?(field)
    end
    remove_column table, field, if_exists: true
  end

  def add_reference_column(table, field, type, multiple: false, source_key: nil, output_field: nil)
    return unless data_source_exists?(table)

    source_key ||= if type == :jsonb
      field.sub(/_ids\z/, "") + "_ids"
    else
      field.sub(/_id\z/, "") + "_id"
    end
    output_field ||= field

    expression = if multiple
      "COALESCE(data -> '#{source_key}', '[]'::jsonb)"
    elsif type == :jsonb
      "COALESCE(data -> '#{source_key}', '[]'::jsonb)"
    else
      "CASE WHEN (data ->> '#{source_key}') ~ '^[0-9]+$' THEN (data ->> '#{source_key}')::bigint END"
    end
    add_column table, output_field, type, as: expression, stored: true unless column_exists?(table, output_field)
    add_index table, output_field, using: :gin if type == :jsonb && !index_exists?(table, output_field)
    add_index table, output_field unless type == :jsonb || index_exists?(table, output_field)
  end

  def create_reference_indexes
    COMPOSITE_REFERENCE_INDEXES.each do |table, indexes|
      indexes.each do |columns|
        add_index table, columns unless index_exists?(table, columns)
      end
    end
  end

  def remove_reference_indexes
    (SINGLE_REFERENCES.keys + MULTI_REFERENCES.keys + DIRECT_ID_FIELDS.keys).uniq.each do |table|
      fields = SINGLE_REFERENCES.fetch(table, {}).keys.map { |field| "#{field}_id" } +
        MULTI_REFERENCES.fetch(table, {}).keys.map { |field| "#{field}_ids" } +
        DIRECT_ID_FIELDS.fetch(table, [])
      fields.uniq.each { |field| remove_index table, field, if_exists: true }
    end
  end

  def add_lookup_key(lookup, label, id)
    if lookup.key?(label) && lookup[label] != id
      lookup[label] = :ambiguous
    else
      lookup[label] ||= id
    end
  end

  def add_target_mapping_reference_ids!
    return unless data_source_exists?(:target_mappings)

    %i[month_id main_activity_id sub_activity_id].each do |column|
      add_column :target_mappings, column, :bigint unless column_exists?(:target_mappings, column)
    end

    month_lookup = lookup_for("module_months", %w[month_name])
    main_lookup = lookup_for("module_main_activities", %w[main_activity_name activity_group_name])
    sub_lookup = lookup_for("module_sub_activities", %w[sub_activity_name activity_name vrp_activity_name])
    select_all("SELECT id, month_name, main_activity_name, activity_name FROM target_mappings").each do |row|
      month_id = month_lookup[normalize_label(row["month_name"])]
      main_id = main_lookup[normalize_label(row["main_activity_name"])]
      sub_id = sub_lookup[normalize_label(row["activity_name"])]
      execute <<~SQL.squish
        UPDATE target_mappings
        SET month_id = #{connection.quote(month_id.is_a?(Integer) ? month_id : nil)},
            main_activity_id = #{connection.quote(main_id.is_a?(Integer) ? main_id : nil)},
            sub_activity_id = #{connection.quote(sub_id.is_a?(Integer) ? sub_id : nil)}
        WHERE id = #{connection.quote(row['id'])}
      SQL
    end
    add_index :target_mappings, :month_id unless index_exists?(:target_mappings, :month_id)
    add_index :target_mappings, :main_activity_id unless index_exists?(:target_mappings, :main_activity_id)
    add_index :target_mappings, :sub_activity_id unless index_exists?(:target_mappings, :sub_activity_id)
  end

  def normalize_label(label)
    label.to_s.sub(/\A\s*\d+\.\s*/, "").squish.downcase
  end

  def parse_json(value)
    value.is_a?(String) ? (JSON.parse(value) rescue {}) : value
  end

  def update_data(table, id, data)
    execute "UPDATE #{connection.quote_table_name(table)} SET data = #{connection.quote(data.to_json)}::jsonb WHERE id = #{connection.quote(id)}"
  end
end
