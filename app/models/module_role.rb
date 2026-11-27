class ModuleRole < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "role-name"
  def self.label_column = :role_name
end
