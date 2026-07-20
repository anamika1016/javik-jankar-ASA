class AddTrainingTargetsToTargetMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :target_mappings, :opg_training_target, :decimal, precision: 18, scale: 4
    add_column :target_mappings, :week_wise_opg_target, :decimal, precision: 18, scale: 4
    add_column :target_mappings, :input_demo_inm_target, :decimal, precision: 18, scale: 4
    add_column :target_mappings, :input_demo_pm_target, :decimal, precision: 18, scale: 4
    add_column :target_mappings, :ffs_target, :decimal, precision: 18, scale: 4
  end
end
