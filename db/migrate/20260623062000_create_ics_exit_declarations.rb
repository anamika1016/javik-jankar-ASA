class CreateIcsExitDeclarations < ActiveRecord::Migration[8.1]
  def change
    create_table :ics_exit_declarations do |t|
      t.references :farmer_farm_information, foreign_key: { to_table: :farmer_farm_information }
      t.string :farm_id
      t.string :farmer_name
      t.string :id_number
      t.text :farmer_address
      t.string :farmer_contact_no
      t.string :farmer_village
      t.string :tracenet_no
      t.string :ics_name
      t.string :grower_group_name
      t.text :exit_reason
      t.string :certification_status
      t.string :new_certification_body
      t.date :declaration_date
      t.string :signature_of_farmer
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :ics_exit_declarations, :farm_id
    add_index :ics_exit_declarations, :farmer_name
    add_index :ics_exit_declarations, :declaration_date
  end
end
