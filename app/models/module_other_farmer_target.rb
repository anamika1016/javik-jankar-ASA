class ModuleOtherFarmerTarget < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "other-target-with-farmer"
  def self.label_column = :month
end
