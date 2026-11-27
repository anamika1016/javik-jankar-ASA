class ModuleStakeholderRole < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "stakeholder-role"
  def self.label_column = :stakeholder_role
end
