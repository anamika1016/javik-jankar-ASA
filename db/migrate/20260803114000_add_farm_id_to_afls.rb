class AddFarmIdToAfls < ActiveRecord::Migration[8.1]
  def change
    add_column :afls, :farm_id, :string
    add_index :afls, :farm_id
  end
end
