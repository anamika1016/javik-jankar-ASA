class CreateContaminationControlRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :contamination_control_records do |t|
      t.string :chance_of_contamination
      t.text :source_details
      t.string :contamination_control_time
      t.string :prevention
      t.string :control
      t.text :remarks
      t.string :status, default: "Active", null: false

      t.timestamps
    end

    add_index :contamination_control_records, :chance_of_contamination, name: "index_contamination_records_on_chance"
    add_index :contamination_control_records, :created_at, name: "index_contamination_records_on_created_at"
  end
end
