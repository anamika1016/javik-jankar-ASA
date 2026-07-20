class LinkFarmerFarmInformationModules < ActiveRecord::Migration[8.1]
  def change
    add_reference :farmer_farm_map_uploads, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_ffmu_on_ffi_id" }

    add_reference :farm_crop_area_details, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_fcad_on_ffi_id" }

    add_reference :seed_planting_materials, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_spm_on_ffi_id" }

    add_reference :soil_conditioner_fertility_input_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_scfi_on_ffi_id" }

    add_reference :on_farm_input_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_ofir_on_ffi_id" }

    add_reference :disease_pest_weed_management_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_dpwmr_on_ffi_id" }

    add_reference :contamination_control_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_ccr_on_ffi_id" }

    add_reference :production_harvest_details, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_phd_on_ffi_id" }

    add_reference :post_harvest_handling_storage_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_phhsr_on_ffi_id" }

    add_reference :sale_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_sr_on_ffi_id" }

    add_reference :dispatch_records, :farmer_farm_information,
      foreign_key: { to_table: :farmer_farm_information },
      index: { name: "idx_dr_on_ffi_id" }
  end
end
