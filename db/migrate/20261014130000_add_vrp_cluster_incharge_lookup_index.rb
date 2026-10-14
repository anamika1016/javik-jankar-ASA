class AddVrpClusterInchargeLookupIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Cluster-scoped pages inspect distinct assignments before loading the
    # matching VRP rows. This supports both the distinct label read and the
    # follow-up exact-label lookup.
    add_index :vrps, :cluster_incharge,
      name: "index_vrps_on_cluster_incharge",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
