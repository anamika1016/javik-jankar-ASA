class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :stakeholder
      t.string :role
      t.string :state
      t.string :district
      t.string :block
      t.string :gram_panchayat
      t.string :village
      t.string :parent_office
      t.string :office
      t.text :full_address
      t.string :pincode
      t.string :first_name
      t.string :last_name
      t.string :gender
      t.integer :age
      t.string :email
      t.string :password
      t.string :user_name, null: false
      t.string :mobile_no
      t.string :emergency_no
      t.string :user_type
      t.string :status, default: "Active", null: false
      t.timestamps
    end

    add_index :users, :user_name
    add_index :users, :email
    add_index :users, :mobile_no
  end
end
