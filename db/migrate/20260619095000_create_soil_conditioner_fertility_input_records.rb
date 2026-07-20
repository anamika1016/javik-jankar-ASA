class CreateSoilConditionerFertilityInputRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :soil_conditioner_fertility_input_records do |t|
      t.string :serial_no
      t.string :farm_plot_no
      t.string :crop_name
      t.string :input_name
      t.string :input_source_brand
      t.string :application_time
      t.string :application_rate
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :soil_conditioner_fertility_input_records, :crop_name, name: "index_soil_conditioner_records_on_crop_name"
    add_index :soil_conditioner_fertility_input_records, :created_at, name: "index_soil_conditioner_records_on_created_at"
  end
end
