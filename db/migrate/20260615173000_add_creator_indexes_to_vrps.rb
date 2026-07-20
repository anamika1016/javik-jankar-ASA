class AddCreatorIndexesToVrps < ActiveRecord::Migration[8.1]
  def change
    add_index :vrps, :created_by_id, if_not_exists: true
    add_index :vrps, :user_id, if_not_exists: true
  end
end
