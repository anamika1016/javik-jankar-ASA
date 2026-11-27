class ModuleSubOffice < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "office-mapping-add"
  def self.label_column = :sub_office_name
end
