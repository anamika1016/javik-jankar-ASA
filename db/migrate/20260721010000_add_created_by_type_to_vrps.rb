class AddCreatedByTypeToVrps < ActiveRecord::Migration[8.0]
  def change
    add_column :vrps, :created_by_type, :string
    add_index :vrps, [ :created_by_type, :created_by_id ]
  end
end
