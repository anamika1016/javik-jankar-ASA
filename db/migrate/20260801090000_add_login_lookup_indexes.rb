class AddLoginLookupIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :users, "LOWER(user_name)", name: "index_users_on_lower_user_name", algorithm: :concurrently, if_not_exists: true
    add_index :users, "LOWER(email)", name: "index_users_on_lower_email", algorithm: :concurrently, if_not_exists: true
    add_index :vrps, "LOWER(user_name)", name: "index_vrps_on_lower_user_name", algorithm: :concurrently, if_not_exists: true
    add_index :vrps, "LOWER(email)", name: "index_vrps_on_lower_email", algorithm: :concurrently, if_not_exists: true

    add_index :module_records,
      "LOWER((data::jsonb ->> 'user_name'))",
      name: "index_module_records_new_users_on_lower_user_name",
      where: "module_slug = 'new-user'",
      algorithm: :concurrently,
      if_not_exists: true
    add_index :module_records,
      "LOWER((data::jsonb ->> 'email'))",
      name: "index_module_records_new_users_on_lower_email",
      where: "module_slug = 'new-user'",
      algorithm: :concurrently,
      if_not_exists: true
    add_index :module_records,
      "((data::jsonb ->> 'mobile_no'))",
      name: "index_module_records_new_users_on_mobile_no",
      where: "module_slug = 'new-user'",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :module_records, name: "index_module_records_new_users_on_mobile_no", algorithm: :concurrently, if_exists: true
    remove_index :module_records, name: "index_module_records_new_users_on_lower_email", algorithm: :concurrently, if_exists: true
    remove_index :module_records, name: "index_module_records_new_users_on_lower_user_name", algorithm: :concurrently, if_exists: true
    remove_index :vrps, name: "index_vrps_on_lower_email", algorithm: :concurrently, if_exists: true
    remove_index :vrps, name: "index_vrps_on_lower_user_name", algorithm: :concurrently, if_exists: true
    remove_index :users, name: "index_users_on_lower_email", algorithm: :concurrently, if_exists: true
    remove_index :users, name: "index_users_on_lower_user_name", algorithm: :concurrently, if_exists: true
  end
end
