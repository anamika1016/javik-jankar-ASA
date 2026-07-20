class AddSubOfficeNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sub_office_name, :string, if_not_exists: true
  end
end
