class PreserveVrpProfileLocationNames < ActiveRecord::Migration[8.1]
  def up
    %i[state_id district_id block_id gram_panchayat_id village_id].each do |column|
      change_column :vrp_profiles, column, :string, using: "#{column}::text"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Location names cannot be converted back to integer IDs without data loss"
  end
end
