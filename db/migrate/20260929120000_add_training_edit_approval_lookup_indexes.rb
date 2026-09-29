class AddTrainingEditApprovalLookupIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :module_records,
      "((data::jsonb ->> 'status'))",
      name: "index_training_edits_on_status",
      where: "module_slug = 'training-form-edit-request'",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :module_records,
      "((data::jsonb ->> 'record_id'))",
      name: "index_training_edits_on_record_id",
      where: "module_slug = 'training-form-edit-request'",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
