class VrpProfile < ApplicationRecord
  belongs_to :vrp

  validates :state_id,
            :district_id,
            :block_id,
            :gram_panchayat_id,
            :village_id,
            presence: true
end
