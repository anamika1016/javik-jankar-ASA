class ModuleJjTransfer < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "jeevika-jankar-transfer"
  def self.label_column = :user_name
end
