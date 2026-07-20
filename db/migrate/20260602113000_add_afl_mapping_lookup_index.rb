class AddAflMappingLookupIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :afls, [:fco_id, :ics_id, :village_id], name: "index_afls_on_mapping_lookup"
  end
end
