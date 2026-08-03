class AddTargetMappingListIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :target_mappings, :updated_at,
      order: { updated_at: :desc },
      algorithm: :concurrently,
      if_not_exists: true

    add_index :target_mappings, [:created_by_type, :created_by_id, :updated_at],
      name: "index_target_mappings_on_creator_and_updated_at",
      order: { updated_at: :desc },
      algorithm: :concurrently,
      if_not_exists: true

    add_index :target_mappings, [:vrp_id, :updated_at],
      name: "index_target_mappings_on_vrp_and_updated_at",
      order: { updated_at: :desc },
      algorithm: :concurrently,
      if_not_exists: true
  end
end
