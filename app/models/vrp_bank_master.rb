class VrpBankMaster < ApplicationRecord
  has_many :vrps, dependent: :destroy
  validates :name, presence: true
end
