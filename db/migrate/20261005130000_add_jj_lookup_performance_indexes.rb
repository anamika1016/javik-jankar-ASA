class AddJjLookupPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :target_mappings, "vrp_id, LOWER(BTRIM(month_name))",
      name: "index_target_mappings_on_owner_normalized_month",
      algorithm: :concurrently, if_not_exists: true
    add_index :module_records, "(data::jsonb ->> 'bill_id')",
      name: "index_jj_bill_history_on_bill_id",
      where: "module_slug = 'jeevika-jankar-bill-approval-history'",
      algorithm: :concurrently, if_not_exists: true
  end
end
