class ModuleOtherFarmerTarget < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "other-target-with-farmer"
  def self.label_column = :month_id
  def self.option_label_key = :month
end
