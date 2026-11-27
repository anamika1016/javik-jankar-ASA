class ModulePaymentDetail < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "jeevika-jankar-payment-detail"
  def self.label_column = :bill_month
end
