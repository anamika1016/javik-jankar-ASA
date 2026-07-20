class CreateProductionHarvestDetails < ActiveRecord::Migration[8.1]
  def change
    create_table :production_harvest_details do |t|
      t.string :farm_plot_name
      t.string :year_season
      t.string :crop_produce_name
      t.decimal :area_hectares, precision: 18, scale: 4
      t.decimal :estimated_production_mt, precision: 18, scale: 4
      t.string :harvest_time
      t.decimal :actual_production_mt, precision: 18, scale: 4
      t.string :status, null: false, default: "Active"

      t.timestamps
    end

    add_index :production_harvest_details, :created_at
    add_index :production_harvest_details, :farm_plot_name
    add_index :production_harvest_details, :crop_produce_name
  end
end
