class ModuleUserHierarchy < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "user-hierarchy-mapping"
  def self.label_column = :level_1_user
end
