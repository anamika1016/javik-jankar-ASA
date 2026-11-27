class ModuleAccessControl < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "access-control"
  def self.label_column = :role_name
end
