class AddAgreementAcceptanceToVrps < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :agreement_accepted_at, :datetime, if_not_exists: true
  end
end
