class ModuleOfficeCategory < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "office-category-add"
  def self.label_column = :office_name
end
