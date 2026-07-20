class CreateVrpIcsMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :vrp_ics_mappings do |t|
      t.references :vrp, null: false, foreign_key: true
      t.string :fco_id, null: false
      t.string :fco_name
      t.string :ics_id, null: false
      t.string :ics_name
      t.string :village_id, null: false
      t.string :village_name
      t.text :afl_ids, null: false

      t.timestamps
    end

    add_index :vrp_ics_mappings, [:vrp_id, :fco_id, :ics_id, :village_id], name: "index_vrp_ics_mappings_on_mapping_scope", unique: true
  end
end
