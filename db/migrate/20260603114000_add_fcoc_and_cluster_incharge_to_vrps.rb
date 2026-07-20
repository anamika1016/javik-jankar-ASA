class AddFcocAndClusterInchargeToVrps < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :fcoc, :string, if_not_exists: true
    add_column :vrps, :cluster_incharge, :string, if_not_exists: true
  end
end
