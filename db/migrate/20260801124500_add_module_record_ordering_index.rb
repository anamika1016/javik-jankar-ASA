class AddModuleRecordOrderingIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :module_records, [:module_slug, :created_at],
      name: "index_module_records_on_slug_and_created_at",
      order: { created_at: :desc },
      algorithm: :concurrently,
      if_not_exists: true
  end
end
