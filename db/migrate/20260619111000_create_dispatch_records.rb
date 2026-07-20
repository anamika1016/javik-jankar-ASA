class CreateDispatchRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :dispatch_records do |t|
      t.string :produce_name
      t.string :organic_status
      t.decimal :quantity_sold_to_ics_kg, precision: 18, scale: 4
      t.date :transport_date
      t.decimal :transport_quantity, precision: 18, scale: 4
      t.string :transport_mode
      t.text :remarks
      t.string :status, null: false, default: "Active"

      t.timestamps
    end

    add_index :dispatch_records, :created_at
    add_index :dispatch_records, :produce_name
    add_index :dispatch_records, :transport_date
  end
end
