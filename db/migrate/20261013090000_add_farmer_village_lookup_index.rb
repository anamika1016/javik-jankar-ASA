class AddFarmerVillageLookupIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # target_live_farmer_ids looks up village_id without fco_id/ics_id.
    # The existing (fco_id, ics_id, village_id) index cannot lead this lookup.
    add_index :afls, :village_id, name: "index_afls_on_village_id",
      algorithm: :concurrently, if_not_exists: true
  end
end
