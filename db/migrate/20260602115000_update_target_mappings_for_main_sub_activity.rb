class UpdateTargetMappingsForMainSubActivity < ActiveRecord::Migration[8.1]
  def change
    add_column :target_mappings, :main_activity_name, :string
    change_column_null :target_mappings, :vrp_ics_mapping_id, true
  end
end
