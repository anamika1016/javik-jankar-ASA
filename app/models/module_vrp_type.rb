class ModuleVrpType < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "add-vrp-type"
  def self.label_column = :vrp_type_name
end
