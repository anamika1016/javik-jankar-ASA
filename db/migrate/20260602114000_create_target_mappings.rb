class CreateTargetMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :target_mappings do |t|
      t.references :vrp, null: false, foreign_key: true
      t.references :vrp_ics_mapping, null: false, foreign_key: true
      t.string :fco_id, null: false
      t.string :fco_name
      t.string :ics_id, null: false
      t.string :ics_name
      t.string :village_id, null: false
      t.string :village_name
      t.integer :farmer_count, default: 0, null: false
      t.string :month_name, null: false
      t.string :activity_name, null: false
      t.decimal :target_quantity, precision: 18, scale: 4, null: false
      t.timestamps
    end

    add_index :target_mappings, [:vrp_id, :vrp_ics_mapping_id, :month_name, :activity_name], name: "index_target_mappings_on_scope"
  end
end
