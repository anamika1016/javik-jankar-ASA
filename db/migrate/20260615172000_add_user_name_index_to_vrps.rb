class AddUserNameIndexToVrps < ActiveRecord::Migration[8.1]
  def change
    add_index :vrps, :user_name, if_not_exists: true
  end
end
