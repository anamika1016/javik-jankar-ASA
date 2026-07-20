class CreateSaleRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :sale_records do |t|
      t.string :produce_name
      t.string :organic_status
      t.decimal :total_output_for_sale_kg, precision: 18, scale: 4
      t.decimal :quantity_sold_to_ics_kg, precision: 18, scale: 4
      t.string :purchase_receipt_no
      t.decimal :balance_qty, precision: 18, scale: 4
      t.text :usage_consumption_other_issues
      t.text :remarks
      t.string :status, null: false, default: "Active"

      t.timestamps
    end

    add_index :sale_records, :created_at
    add_index :sale_records, :produce_name
    add_index :sale_records, :organic_status
  end
end
