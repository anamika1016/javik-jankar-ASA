class AddFarmerRegistrationFields < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :bank_name, :string
    add_column :vrps, :ics_master_ids, :text
    add_column :users, :ics, :string

    change_column_null :vrps, :vrp_bank_master_id, true
  end
end
