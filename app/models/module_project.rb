class ModuleProject < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "project-master"
  def self.label_column = :project_name
end
