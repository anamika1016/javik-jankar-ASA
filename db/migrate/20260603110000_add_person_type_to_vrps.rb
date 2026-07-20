class AddPersonTypeToVrps < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :person_type, :string, if_not_exists: true
  end
end
