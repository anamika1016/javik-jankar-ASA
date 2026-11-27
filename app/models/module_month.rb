class ModuleMonth < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "month-master"
  def self.label_column = :month_name
end
