class CreateModuleRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :module_records do |t|
      t.string :module_slug, null: false
      t.text :data, null: false

      t.timestamps
    end

    add_index :module_records, :module_slug
  end
end
