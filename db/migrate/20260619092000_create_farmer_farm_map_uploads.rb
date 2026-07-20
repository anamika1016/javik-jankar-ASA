class CreateFarmerFarmMapUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :farmer_farm_map_uploads do |t|
      t.string :map_type, null: false
      t.decimal :latitude, precision: 20, scale: 8
      t.decimal :longitude, precision: 20, scale: 8
      t.decimal :gps_accuracy, precision: 12, scale: 4
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :farmer_farm_map_uploads, :map_type
    add_index :farmer_farm_map_uploads, :created_at
  end
end
