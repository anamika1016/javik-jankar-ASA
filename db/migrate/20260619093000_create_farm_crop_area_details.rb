class CreateFarmCropAreaDetails < ActiveRecord::Migration[8.1]
  def change
    create_table :farm_crop_area_details do |t|
      t.string :record_title
      t.string :crop_name
      t.decimal :area_hectares, precision: 18, scale: 4
      t.string :year_season_production
      t.string :perennial_age_plantation_time
      t.string :production_method
      t.string :remarks
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :farm_crop_area_details, :record_title
    add_index :farm_crop_area_details, :crop_name
    add_index :farm_crop_area_details, :created_at
  end
end
