class AddDirectFieldsToFarmCropAreaDetails < ActiveRecord::Migration[8.1]
  def change
    return unless table_exists?(:farm_crop_area_details)

    add_column :farm_crop_area_details, :crop_name, :string unless column_exists?(:farm_crop_area_details, :crop_name)
    add_column :farm_crop_area_details, :area_hectares, :decimal, precision: 18, scale: 4 unless column_exists?(:farm_crop_area_details, :area_hectares)
    add_column :farm_crop_area_details, :year_season_production, :string unless column_exists?(:farm_crop_area_details, :year_season_production)
    add_column :farm_crop_area_details, :perennial_age_plantation_time, :string unless column_exists?(:farm_crop_area_details, :perennial_age_plantation_time)
    add_column :farm_crop_area_details, :production_method, :string unless column_exists?(:farm_crop_area_details, :production_method)
    add_column :farm_crop_area_details, :remarks, :string unless column_exists?(:farm_crop_area_details, :remarks)
    add_index :farm_crop_area_details, :crop_name unless index_exists?(:farm_crop_area_details, :crop_name)
  end
end
