class AddLoginAndRoleFieldsToVrps < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :stakeholder, :string, if_not_exists: true
    add_column :vrps, :stakeholder_role, :string, if_not_exists: true
    add_column :vrps, :role, :string, if_not_exists: true
    add_column :vrps, :user_management_role, :string, if_not_exists: true
    add_column :vrps, :emergency_no, :string, if_not_exists: true
    add_column :vrps, :user_name, :string, if_not_exists: true
    add_column :vrps, :password, :string, if_not_exists: true
  end
end
