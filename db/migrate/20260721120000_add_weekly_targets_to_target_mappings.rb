class AddWeeklyTargetsToTargetMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :target_mappings, :week_1_target, :integer
    add_column :target_mappings, :week_2_target, :integer
    add_column :target_mappings, :week_3_target, :integer
    add_column :target_mappings, :week_4_target, :integer
  end
end
