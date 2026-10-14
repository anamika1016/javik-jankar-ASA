class AddTrainingFormReadPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Matches active_module_records_scope("training-form") when a dashboard or
    # bill filters by month and orders newest records first.
    active_predicate = <<~SQL.squish
      COALESCE(LOWER(BTRIM(data::jsonb ->> 'deleted')), '') NOT IN ('1', 'true', 'yes', 'deleted')
      AND COALESCE(LOWER(BTRIM(data::jsonb ->> 'is_deleted')), '') NOT IN ('1', 'true', 'yes', 'deleted')
      AND COALESCE(LOWER(BTRIM(data::jsonb ->> 'discarded')), '') NOT IN ('1', 'true', 'yes', 'deleted')
      AND (COALESCE(BTRIM(data::jsonb ->> 'status'), '') = '' OR LOWER(BTRIM(data::jsonb ->> 'status')) = 'active')
    SQL

    add_index :module_records,
      "module_slug, LOWER(BTRIM(data::jsonb ->> 'month')), created_at DESC",
      name: "index_module_records_active_slug_month_created_at",
      where: active_predicate,
      algorithm: :concurrently,
      if_not_exists: true

    # Supports the newest-revision-per-training-record lookup used by billing
    # and dashboard participation calculations.
    add_index :module_records,
      "((data::jsonb ->> 'record_id')), id DESC",
      name: "index_training_edits_on_record_id_and_latest_id",
      where: "module_slug = 'training-form-edit-request'",
      algorithm: :concurrently,
      if_not_exists: true

    # The layout asks for pending edit approvals in newest-first order.  The
    # existing status-only index still leaves PostgreSQL to sort those rows.
    add_index :module_records,
      "((data::jsonb ->> 'status')), id DESC",
      name: "index_training_edits_on_status_and_latest_id",
      where: "module_slug = 'training-form-edit-request'",
      algorithm: :concurrently,
      if_not_exists: true

    # Keep the legacy user lookup case-sensitive, exactly as the helper is.
    # The older lower(user_name) index cannot serve that predicate or its
    # updated_at ordering.
    add_index :module_records,
      "((data::jsonb ->> 'user_name')), updated_at DESC",
      name: "index_module_records_new_users_on_user_name_and_updated_at",
      where: "module_slug = 'new-user'",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
