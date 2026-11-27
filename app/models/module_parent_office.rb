class ModuleParentOffice < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "parent-office-add"
  def self.label_column = :parent_office_name
end
