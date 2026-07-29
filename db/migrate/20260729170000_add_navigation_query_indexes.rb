class AddNavigationQueryIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :module_records, [:module_slug, :created_at],
      name: "idx_module_records_slug_created_at",
      if_not_exists: true
    add_index :module_records, [:module_slug, :updated_at],
      name: "idx_module_records_slug_updated_at",
      if_not_exists: true

    add_index :target_mappings, [:vrp_id, :updated_at],
      name: "idx_target_mappings_vrp_updated_at",
      if_not_exists: true
    add_index :target_mappings, [:month_name, :main_activity_name, :activity_name],
      name: "idx_target_mappings_activity_period",
      if_not_exists: true

    add_index :vrps, [:is_deleted, :status],
      name: "idx_vrps_visible_status",
      if_not_exists: true
    add_index :vrps, [:is_deleted, :updated_at],
      name: "idx_vrps_visible_updated_at",
      if_not_exists: true
  end
end
