class AddOfficeCategoryAndOfficeNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :office_category, :string
    add_column :users, :office_name, :string
  end
end
