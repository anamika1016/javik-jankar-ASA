class CreateSeedPlantingMaterials < ActiveRecord::Migration[8.1]
  def change
    create_table :seed_planting_materials do |t|
      t.string :serial_no
      t.string :crop_name
      t.string :variety
      t.date :purchase_date
      t.text :supplier_name_address
      t.string :seed_type
      t.text :seed_treatment_details
      t.decimal :seed_quantity, precision: 18, scale: 4
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :seed_planting_materials, :crop_name
    add_index :seed_planting_materials, :created_at
  end
end
