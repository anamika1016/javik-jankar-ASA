class CreateVrpRegistrationTables < ActiveRecord::Migration[8.1]
  def change
    create_table :vrp_bank_masters do |t|
      t.string :name, null: false
      t.boolean :is_active, default: true, null: false
      t.boolean :is_deleted, default: false, null: false

      t.timestamps
    end

    create_table :vrp_types do |t|
      t.string :type_name, null: false
      t.boolean :is_active, default: true, null: false
      t.boolean :is_deleted, default: false, null: false

      t.timestamps
    end

    create_table :vrps do |t|
      t.string :name, null: false
      t.string :father_husband_name, null: false
      t.integer :gender, null: false
      t.date :date_of_birth, null: false
      t.date :date_of_joining, null: false
      t.string :aadhar_no, null: false
      t.string :account_no, null: false
      t.string :branch, null: false
      t.string :ifsc_code, null: false
      t.references :vrp_bank_master, null: false, foreign_key: true
      t.text :address, null: false
      t.string :mobile_no, null: false
      t.string :email, null: false
      t.integer :experience_in_years, null: false
      t.integer :office_detail_id, null: false
      t.integer :to_office_detail_id, null: false
      t.integer :user_id
      t.integer :created_by_id
      t.integer :status, default: 25, null: false
      t.boolean :is_active, default: true, null: false
      t.boolean :is_deleted, default: false, null: false
      t.text :vrp_type_ids
      t.text :project_master_ids
      t.text :gram_panchayat_ids
      t.text :village_ids

      t.timestamps
    end

    add_index :vrps, :mobile_no
    add_index :vrps, :email
    add_index :vrps, :aadhar_no

    create_table :vrp_profiles do |t|
      t.references :vrp, null: false, foreign_key: true
      t.integer :state_id, null: false
      t.integer :district_id, null: false
      t.integer :block_id, null: false
      t.integer :gram_panchayat_id, null: false
      t.integer :village_id, null: false

      t.timestamps
    end

    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false

      t.index :key, unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.datetime :created_at, null: false

      t.index [:record_type, :record_id, :name, :blob_id], unique: true, name: :index_active_storage_attachments_uniqueness
    end

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, index: false, foreign_key: { to_table: :active_storage_blobs }
      t.string :variation_digest, null: false

      t.index [:blob_id, :variation_digest], unique: true, name: :index_active_storage_variant_records_uniqueness
    end
  end
end
