class AddCcTargetToTargetMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :target_mappings, :cc_target, :decimal, precision: 18, scale: 4
  end
end
