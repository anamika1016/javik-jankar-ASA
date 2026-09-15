class AddReadPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :module_records, "(data::jsonb)", using: :gin,
      name: "index_module_records_on_json_data", algorithm: :concurrently, if_not_exists: true
    add_index :target_mappings, "LOWER(BTRIM(month_name))",
      name: "index_target_mappings_on_normalized_month", algorithm: :concurrently, if_not_exists: true
    add_index :vrps, :status,
      name: "index_vrps_on_status", algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :vrps, name: "index_vrps_on_status", algorithm: :concurrently, if_exists: true
    remove_index :target_mappings, name: "index_target_mappings_on_normalized_month", algorithm: :concurrently, if_exists: true
    remove_index :module_records, name: "index_module_records_on_json_data", algorithm: :concurrently, if_exists: true
  end
end
