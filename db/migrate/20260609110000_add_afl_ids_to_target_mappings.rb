class AddAflIdsToTargetMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :target_mappings, :afl_ids, :text, null: false, default: "[]"
  end
end
