class ModuleSubActivity < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "add-vrp-activity"
  def self.label_column = :sub_activity_name
end
