# Removing this feature deletes its table data when deployed. Rollback restores
# table definitions, not deleted rows. Historical migrations remain unchanged.
class RemoveFarmerFarmInformationFeature < ActiveRecord::Migration[8.1]
  def change
    drop_table "farmer_farm_map_uploads" do |t|
      t.datetime "created_at", null: false
      t.bigint "farmer_farm_information_id"
      t.decimal "gps_accuracy", precision: 12, scale: 4
      t.decimal "latitude", precision: 20, scale: 8
      t.decimal "longitude", precision: 20, scale: 8
      t.string "map_type", null: false
      t.string "status", default: "Active", null: false
      t.datetime "updated_at", null: false
      t.index ["created_at"], name: "index_farmer_farm_map_uploads_on_created_at"
      t.index ["farmer_farm_information_id"], name: "idx_ffmu_on_ffi_id"
      t.index ["map_type"], name: "index_farmer_farm_map_uploads_on_map_type"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "farm_crop_area_details" do |t|
      t.decimal "area_hectares", precision: 18, scale: 4
      t.datetime "created_at", null: false
      t.string "crop_name"
      t.bigint "farmer_farm_information_id"
      t.string "perennial_age_plantation_time"
      t.string "production_method"
      t.string "record_title"
      t.string "remarks"
      t.string "status", default: "Active", null: false
      t.datetime "updated_at", null: false
      t.string "year_season_production"
      t.index ["created_at"], name: "index_farm_crop_area_details_on_created_at"
      t.index ["crop_name"], name: "index_farm_crop_area_details_on_crop_name"
      t.index ["farmer_farm_information_id"], name: "idx_fcad_on_ffi_id"
      t.index ["record_title"], name: "index_farm_crop_area_details_on_record_title"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "seed_planting_materials" do |t|
      t.datetime "created_at", null: false
      t.string "crop_name"
      t.bigint "farmer_farm_information_id"
      t.date "purchase_date"
      t.decimal "seed_quantity", precision: 18, scale: 4
      t.text "seed_treatment_details"
      t.string "seed_type"
      t.string "serial_no"
      t.string "status", default: "Active", null: false
      t.text "supplier_name_address"
      t.datetime "updated_at", null: false
      t.string "variety"
      t.index ["created_at"], name: "index_seed_planting_materials_on_created_at"
      t.index ["crop_name"], name: "index_seed_planting_materials_on_crop_name"
      t.index ["farmer_farm_information_id"], name: "idx_spm_on_ffi_id"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "soil_conditioner_fertility_input_records" do |t|
      t.string "application_rate"
      t.string "application_time"
      t.datetime "created_at", null: false
      t.string "crop_name"
      t.string "farm_plot_no"
      t.bigint "farmer_farm_information_id"
      t.string "input_name"
      t.string "input_source_brand"
      t.string "serial_no"
      t.string "status", default: "Active", null: false
      t.datetime "updated_at", null: false
      t.index ["created_at"], name: "index_soil_conditioner_records_on_created_at"
      t.index ["crop_name"], name: "index_soil_conditioner_records_on_crop_name"
      t.index ["farmer_farm_information_id"], name: "idx_scfi_on_ffi_id"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "on_farm_input_records" do |t|
      t.datetime "created_at", null: false
      t.bigint "farmer_farm_information_id"
      t.string "input_name"
      t.date "preparation_date"
      t.decimal "prepared_quantity", precision: 18, scale: 4
      t.text "raw_material_details"
      t.string "serial_no"
      t.string "status", default: "Active", null: false
      t.datetime "updated_at", null: false
      t.index ["created_at"], name: "index_on_farm_input_records_on_created_at"
      t.index ["farmer_farm_information_id"], name: "idx_ofir_on_ffi_id"
      t.index ["input_name"], name: "index_on_farm_input_records_on_input_name"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "disease_pest_weed_management_records" do |t|
      t.string "application_rate"
      t.decimal "area", precision: 18, scale: 4
      t.datetime "created_at", null: false
      t.string "crop_name"
      t.string "farm_plot_no"
      t.bigint "farmer_farm_information_id"
      t.string "input_source_brand"
      t.string "pest_disease_weed_name"
      t.string "status", default: "Active", null: false
      t.string "treatment_name"
      t.string "treatment_time"
      t.datetime "updated_at", null: false
      t.index ["created_at"], name: "index_disease_pest_records_on_created_at"
      t.index ["crop_name"], name: "index_disease_pest_records_on_crop_name"
      t.index ["farmer_farm_information_id"], name: "idx_dpwmr_on_ffi_id"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "contamination_control_records" do |t|
      t.string "chance_of_contamination"
      t.string "contamination_control_time"
      t.string "control"
      t.datetime "created_at", null: false
      t.bigint "farmer_farm_information_id"
      t.string "prevention"
      t.text "remarks"
      t.text "source_details"
      t.string "status", default: "Active", null: false
      t.datetime "updated_at", null: false
      t.index ["chance_of_contamination"], name: "index_contamination_records_on_chance"
      t.index ["created_at"], name: "index_contamination_records_on_created_at"
      t.index ["farmer_farm_information_id"], name: "idx_ccr_on_ffi_id"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "production_harvest_details" do |t|
      t.decimal "actual_production_mt", precision: 18, scale: 4
      t.decimal "area_hectares", precision: 18, scale: 4
      t.datetime "created_at", null: false
      t.string "crop_produce_name"
      t.decimal "estimated_production_mt", precision: 18, scale: 4
      t.string "farm_plot_name"
      t.bigint "farmer_farm_information_id"
      t.string "harvest_time"
      t.string "status", default: "Active", null: false
      t.datetime "updated_at", null: false
      t.string "year_season"
      t.index ["created_at"], name: "index_production_harvest_details_on_created_at"
      t.index ["crop_produce_name"], name: "index_production_harvest_details_on_crop_produce_name"
      t.index ["farm_plot_name"], name: "index_production_harvest_details_on_farm_plot_name"
      t.index ["farmer_farm_information_id"], name: "idx_phd_on_ffi_id"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "post_harvest_handling_storage_records" do |t|
      t.datetime "created_at", null: false
      t.string "crop_name"
      t.bigint "farmer_farm_information_id"
      t.string "packing_material"
      t.text "post_harvest_treatment"
      t.string "produce_name"
      t.string "status", default: "Active", null: false
      t.string "storage_area"
      t.datetime "updated_at", null: false
      t.index ["created_at"], name: "idx_post_harvest_storage_on_created_at"
      t.index ["crop_name"], name: "idx_post_harvest_storage_on_crop_name"
      t.index ["farmer_farm_information_id"], name: "idx_phhsr_on_ffi_id"
      t.index ["produce_name"], name: "idx_post_harvest_storage_on_produce_name"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "sale_records" do |t|
      t.decimal "balance_qty", precision: 18, scale: 4
      t.datetime "created_at", null: false
      t.bigint "farmer_farm_information_id"
      t.string "organic_status"
      t.string "produce_name"
      t.string "purchase_receipt_no"
      t.decimal "quantity_sold_to_ics_kg", precision: 18, scale: 4
      t.text "remarks"
      t.string "status", default: "Active", null: false
      t.decimal "total_output_for_sale_kg", precision: 18, scale: 4
      t.datetime "updated_at", null: false
      t.text "usage_consumption_other_issues"
      t.index ["created_at"], name: "index_sale_records_on_created_at"
      t.index ["farmer_farm_information_id"], name: "idx_sr_on_ffi_id"
      t.index ["organic_status"], name: "index_sale_records_on_organic_status"
      t.index ["produce_name"], name: "index_sale_records_on_produce_name"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "dispatch_records" do |t|
      t.datetime "created_at", null: false
      t.bigint "farmer_farm_information_id"
      t.string "organic_status"
      t.string "produce_name"
      t.decimal "quantity_sold_to_ics_kg", precision: 18, scale: 4
      t.text "remarks"
      t.string "status", default: "Active", null: false
      t.date "transport_date"
      t.string "transport_mode"
      t.decimal "transport_quantity", precision: 18, scale: 4
      t.datetime "updated_at", null: false
      t.index ["created_at"], name: "index_dispatch_records_on_created_at"
      t.index ["farmer_farm_information_id"], name: "idx_dr_on_ffi_id"
      t.index ["produce_name"], name: "index_dispatch_records_on_produce_name"
      t.index ["transport_date"], name: "index_dispatch_records_on_transport_date"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "ics_exit_declarations" do |t|
      t.string "certification_status"
      t.datetime "created_at", null: false
      t.date "declaration_date"
      t.text "exit_reason"
      t.string "farm_id"
      t.text "farmer_address"
      t.string "farmer_contact_no"
      t.bigint "farmer_farm_information_id"
      t.string "farmer_name"
      t.string "farmer_village"
      t.string "grower_group_name"
      t.string "ics_name"
      t.string "id_number"
      t.string "new_certification_body"
      t.string "signature_of_farmer"
      t.string "status", default: "Active", null: false
      t.string "tracenet_no"
      t.datetime "updated_at", null: false
      t.index ["declaration_date"], name: "index_ics_exit_declarations_on_declaration_date"
      t.index ["farm_id"], name: "index_ics_exit_declarations_on_farm_id"
      t.index ["farmer_farm_information_id"], name: "index_ics_exit_declarations_on_farmer_farm_information_id"
      t.index ["farmer_name"], name: "index_ics_exit_declarations_on_farmer_name"
      t.foreign_key "farmer_farm_information", column: "farmer_farm_information_id"
    end

    drop_table "farmer_farm_information" do |t|
      t.string "aadhar_number"
      t.string "certification_status"
      t.datetime "created_at", null: false
      t.text "crops_under_organic_production_area"
      t.string "current_crop_year"
      t.date "date_of_joining_ics"
      t.text "farm_address"
      t.string "farm_block"
      t.string "farm_district"
      t.string "farm_gram"
      t.string "farm_id"
      t.string "farm_name"
      t.string "farm_state"
      t.string "farm_village"
      t.text "farmer_address"
      t.string "farmer_block"
      t.string "farmer_contact_no"
      t.string "farmer_district"
      t.string "farmer_gram"
      t.string "farmer_name"
      t.string "farmer_pincode"
      t.string "farmer_state"
      t.string "farmer_village"
      t.string "father_mother_name"
      t.string "ics_name"
      t.string "khasra_no"
      t.text "land_details"
      t.decimal "latitude", precision: 20, scale: 8
      t.decimal "longitude", precision: 20, scale: 8
      t.string "name_of_accredited_certification_body"
      t.integer "no_of_farms_plots"
      t.string "organic_production_started_year"
      t.text "other_crops_name_area"
      t.string "present_production_technique"
      t.string "season"
      t.string "status", default: "Active", null: false
      t.decimal "total_land", precision: 18, scale: 4
      t.decimal "total_land_offered_for_organic_certification", precision: 18, scale: 4
      t.string "tracenet_no"
      t.datetime "updated_at", null: false
      t.index ["farm_id"], name: "index_farmer_farm_information_on_farm_id"
      t.index ["farmer_name"], name: "index_farmer_farm_information_on_farmer_name"
      t.index ["tracenet_no"], name: "index_farmer_farm_information_on_tracenet_no"
    end

  end
end
