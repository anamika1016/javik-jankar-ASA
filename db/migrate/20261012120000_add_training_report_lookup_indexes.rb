class AddTrainingReportLookupIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Same normalized expressions used by the VRP participation queries.
    add_index :afls, "LOWER(BTRIM(fco_id))", name: "index_afls_on_normalized_fco_id",
      algorithm: :concurrently, if_not_exists: true
    add_index :afls, "LOWER(BTRIM(fco))", name: "index_afls_on_normalized_fco_name",
      algorithm: :concurrently, if_not_exists: true
    add_index :module_records, "module_slug, LOWER(BTRIM(data::jsonb ->> 'month'))",
      name: "index_module_records_on_slug_normalized_month", algorithm: :concurrently, if_not_exists: true
  end
end
