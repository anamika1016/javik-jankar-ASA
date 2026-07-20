class AddCreatorToMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :vrp_ics_mappings, :created_by_type, :string
    add_column :vrp_ics_mappings, :created_by_id, :bigint
    add_index :vrp_ics_mappings, [:created_by_type, :created_by_id], name: "index_vrp_ics_mappings_on_creator"

    add_column :target_mappings, :created_by_type, :string
    add_column :target_mappings, :created_by_id, :bigint
    add_index :target_mappings, [:created_by_type, :created_by_id], name: "index_target_mappings_on_creator"
  end
end
