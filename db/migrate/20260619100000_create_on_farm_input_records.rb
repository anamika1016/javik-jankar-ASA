class CreateOnFarmInputRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :on_farm_input_records do |t|
      t.string :serial_no
      t.string :input_name
      t.date :preparation_date
      t.text :raw_material_details
      t.decimal :prepared_quantity, precision: 18, scale: 4
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :on_farm_input_records, :input_name
    add_index :on_farm_input_records, :created_at
  end
end
