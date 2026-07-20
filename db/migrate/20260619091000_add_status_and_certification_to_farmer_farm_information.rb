class AddStatusAndCertificationToFarmerFarmInformation < ActiveRecord::Migration[8.1]
  def change
    return unless table_exists?(:farmer_farm_information)

    add_column :farmer_farm_information, :status, :string, default: "Active", null: false unless column_exists?(:farmer_farm_information, :status)
    add_column :farmer_farm_information, :other_crops_name_area, :text unless column_exists?(:farmer_farm_information, :other_crops_name_area)
    add_column :farmer_farm_information, :certification_status, :string unless column_exists?(:farmer_farm_information, :certification_status)
    add_column :farmer_farm_information, :name_of_accredited_certification_body, :string unless column_exists?(:farmer_farm_information, :name_of_accredited_certification_body)
  end
end
