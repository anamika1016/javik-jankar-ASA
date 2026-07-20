class AddCompletionDateToTargetMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :target_mappings, :completion_date, :date
  end
end
