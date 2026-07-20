class CreateDiseasePestWeedManagementRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :disease_pest_weed_management_records do |t|
      t.string :farm_plot_no
      t.decimal :area, precision: 18, scale: 4
      t.string :crop_name
      t.string :pest_disease_weed_name
      t.string :treatment_name
      t.string :treatment_time
      t.string :input_source_brand
      t.string :application_rate
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :disease_pest_weed_management_records, :crop_name, name: "index_disease_pest_records_on_crop_name"
    add_index :disease_pest_weed_management_records, :created_at, name: "index_disease_pest_records_on_created_at"
  end
end
