class ModuleStakeholder < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "stakeholder-master"
  def self.label_column = :stakeholder_name
end
