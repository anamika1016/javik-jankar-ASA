class ModuleAccessControl < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "access-control"
  def self.label_column = :role_name_id
  def self.option_label_key = :role_name
end
