class ModuleTraining < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "training-form"
  def self.label_column = :month_id
  def self.option_label_key = :month
end
