class ModuleOtherTarget < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "other-target"
  def self.label_column = :month
end
