class ModuleMainActivity < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "add-activity-group"
  def self.label_column = :main_activity_name
end
