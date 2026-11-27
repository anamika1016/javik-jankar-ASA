class ModuleUserHierarchy < ApplicationRecord
  include ModuleMasterRecord

  def self.module_slug = "user-hierarchy-mapping"
  def self.label_column = :level_1_user_id

  def self.option_pairs(_column = label_column)
    active.catalogue_order
      .where("NULLIF(BTRIM(data ->> 'level_1_user'), '') IS NOT NULL")
      .pluck(Arel.sql("data ->> 'level_1_user'"), :id)
  end
end
