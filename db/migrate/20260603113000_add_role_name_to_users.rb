class AddRoleNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role_name, :string, if_not_exists: true
  end
end
