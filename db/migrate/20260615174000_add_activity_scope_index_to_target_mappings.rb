class AddActivityScopeIndexToTargetMappings < ActiveRecord::Migration[8.1]
  def change
    add_index :target_mappings, [:fco_id, :ics_id, :village_id, :main_activity_name, :activity_name], name: "index_target_mappings_on_activity_scope", if_not_exists: true
  end
end
