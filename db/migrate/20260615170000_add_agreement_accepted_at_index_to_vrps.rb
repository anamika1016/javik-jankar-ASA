class AddAgreementAcceptedAtIndexToVrps < ActiveRecord::Migration[8.1]
  def change
    add_index :vrps, :agreement_accepted_at, if_not_exists: true
  end
end
