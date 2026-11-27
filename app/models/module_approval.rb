class ModuleApproval < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "approval-master"
  def self.label_column = :module_name
end
