class AddToNameToVrps < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :to_name, :string, if_not_exists: true
  end
end
