class AddCreatedAtIndexToAfls < ActiveRecord::Migration[8.1]
  def change
    add_index :afls, :created_at
  end
end
