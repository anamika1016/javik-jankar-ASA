class AddUsersUpdatedAtLookupIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :users, :updated_at,
      order: { updated_at: :desc },
      name: "index_users_on_updated_at_desc",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
