class AddAgreementVillageLookupIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # AgreementVillageName resolves legacy village IDs against these three
    # tables after checking the module-record catalogue.  Their existing
    # composite indexes start with unrelated columns, so they cannot serve the
    # village_id-only batch lookups used by the agreement list.
    add_index :target_mappings, :village_id,
      name: "index_target_mappings_on_village_id_for_agreements",
      algorithm: :concurrently, if_not_exists: true
    add_index :vrp_ics_mappings, :village_id,
      name: "index_vrp_ics_mappings_on_village_id_for_agreements",
      algorithm: :concurrently, if_not_exists: true

    # Legacy village records can store the identifier under either JSON key.
    # Keep each partial index small and make the resolver's exact predicate
    # indexable without altering its precedence or fallback behavior.
    add_index :module_records,
      "(data::jsonb ->> 'village_id')",
      name: "index_module_records_village_id_lookup",
      where: "module_slug IN ('village-master', 'lg-directory-list')",
      algorithm: :concurrently, if_not_exists: true
    add_index :module_records,
      "(data::jsonb ->> 'village_code')",
      name: "index_module_records_village_code_lookup",
      where: "module_slug IN ('village-master', 'lg-directory-list')",
      algorithm: :concurrently, if_not_exists: true
  end
end
