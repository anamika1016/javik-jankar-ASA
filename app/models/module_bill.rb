class ModuleBill < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "jeevika-jankar-bill-process"
  def self.label_column = :bill_month
end
