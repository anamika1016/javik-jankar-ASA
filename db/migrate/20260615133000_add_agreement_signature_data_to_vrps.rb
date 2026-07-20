class AddAgreementSignatureDataToVrps < ActiveRecord::Migration[8.1]
  def change
    add_column :vrps, :agreement_signature_data, :text, if_not_exists: true
  end
end
