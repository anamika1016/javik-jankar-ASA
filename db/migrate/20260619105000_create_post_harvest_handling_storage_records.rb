class CreatePostHarvestHandlingStorageRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :post_harvest_handling_storage_records do |t|
      t.string :crop_name
      t.text :post_harvest_treatment
      t.string :produce_name
      t.string :packing_material
      t.string :storage_area
      t.string :status, null: false, default: "Active"

      t.timestamps
    end

    add_index :post_harvest_handling_storage_records, :created_at, name: "idx_post_harvest_storage_on_created_at"
    add_index :post_harvest_handling_storage_records, :crop_name, name: "idx_post_harvest_storage_on_crop_name"
    add_index :post_harvest_handling_storage_records, :produce_name, name: "idx_post_harvest_storage_on_produce_name"
  end
end
