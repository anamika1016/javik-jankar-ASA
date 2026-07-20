class CreateFarmerFarmInformation < ActiveRecord::Migration[8.1]
  def change
    create_table :farmer_farm_information do |t|
      t.string :farm_id
      t.string :ics_name
      t.string :current_crop_year
      t.string :season
      t.string :farmer_name
      t.string :tracenet_no
      t.string :father_mother_name
      t.string :aadhar_number

      t.text :farmer_address
      t.string :farmer_pincode
      t.string :farmer_contact_no
      t.string :farmer_state
      t.string :farmer_district
      t.string :farmer_block
      t.string :farmer_gram
      t.string :farmer_village

      t.string :farm_name
      t.text :farm_address
      t.string :farm_state
      t.string :farm_district
      t.string :farm_block
      t.string :farm_gram
      t.string :farm_village
      t.decimal :latitude, precision: 20, scale: 8
      t.decimal :longitude, precision: 20, scale: 8
      t.string :khasra_no

      t.text :land_details
      t.decimal :total_land, precision: 18, scale: 4
      t.integer :no_of_farms_plots
      t.decimal :total_land_offered_for_organic_certification, precision: 18, scale: 4
      t.string :organic_production_started_year
      t.date :date_of_joining_ics
      t.string :present_production_technique
      t.text :crops_under_organic_production_area
      t.text :other_crops_name_area
      t.string :certification_status
      t.string :name_of_accredited_certification_body
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :farmer_farm_information, :farm_id
    add_index :farmer_farm_information, :tracenet_no
    add_index :farmer_farm_information, :farmer_name
  end
end
