class AddActiveModuleCatalogueIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Exact predicates from active_module_records_scope_for_all_modules, so
    # dropdown queries can skip inactive/deleted payloads before JSON projection.
    predicate = <<~SQL.squish
      COALESCE(LOWER(BTRIM(data::jsonb ->> 'deleted')), '') NOT IN ('1', 'true', 'yes', 'deleted')
      AND COALESCE(LOWER(BTRIM(data::jsonb ->> 'is_deleted')), '') NOT IN ('1', 'true', 'yes', 'deleted')
      AND COALESCE(LOWER(BTRIM(data::jsonb ->> 'discarded')), '') NOT IN ('1', 'true', 'yes', 'deleted')
      AND (COALESCE(BTRIM(data::jsonb ->> 'status'), '') = '' OR LOWER(BTRIM(data::jsonb ->> 'status')) = 'active')
    SQL
    add_index :module_records, [:module_slug, :created_at],
      name: "index_module_records_on_active_catalogue",
      order: { created_at: :desc }, where: predicate,
      algorithm: :concurrently, if_not_exists: true
  end
end
