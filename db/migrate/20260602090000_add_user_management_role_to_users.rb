class AddUserManagementRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :stakeholder_role, :string, if_not_exists: true
    add_column :users, :user_management_role, :string, if_not_exists: true
  end
end
