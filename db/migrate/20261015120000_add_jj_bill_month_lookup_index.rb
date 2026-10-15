class AddJjBillMonthLookupIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :module_records,
      "module_slug, (data::jsonb ->> 'bill_month')",
      name: "index_jj_bills_on_module_slug_and_bill_month",
      where: "module_slug = 'jeevika-jankar-bill-process'",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :module_records,
      name: "index_jj_bills_on_module_slug_and_bill_month",
      algorithm: :concurrently,
      if_exists: true
  end
end
