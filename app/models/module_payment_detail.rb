class ModulePaymentDetail < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "jeevika-jankar-payment-detail"
  def self.label_column = :bill_month_id
  def self.option_label_key = :bill_month
end
