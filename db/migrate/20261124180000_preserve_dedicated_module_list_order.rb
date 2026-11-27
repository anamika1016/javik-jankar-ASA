class PreserveDedicatedModuleListOrder < ActiveRecord::Migration[8.1]
  def up
    # Existing Ruby list sorts retain input order for equal labels. Capture the
    # source heap order once so moving tables does not reorder those ties.
    # The archive-to-dedicated bridge is already active when this migration
    # runs.  Capturing the legacy tie order must not block live saves.
    execute "CREATE SEQUENCE module_entry_order_seq AS bigint"
    add_column :module_entry_identities, :storage_order, :bigint
    execute <<~SQL
      WITH original_order AS (SELECT id, row_number() OVER (ORDER BY ctid) AS position FROM module_records)
      UPDATE module_entry_identities identities SET storage_order = original_order.position
      FROM original_order WHERE identities.id = original_order.id
    SQL
    execute "SELECT setval('module_entry_order_seq', GREATEST((SELECT COALESCE(MAX(storage_order),0) FROM module_entry_identities),1))"
    execute "UPDATE module_entry_identities SET storage_order = nextval('module_entry_order_seq') WHERE storage_order IS NULL"
    change_column_default :module_entry_identities, :storage_order, -> { "nextval('module_entry_order_seq')" }
    change_column_null :module_entry_identities, :storage_order, false
    %w[module_entries module_entry_payloads].each do |view|
      definition = select_value("SELECT pg_get_viewdef(#{connection.quote(view)}::regclass, true)").strip.sub(/;\z/, '')
      execute <<~SQL
        CREATE OR REPLACE VIEW #{view} AS
        SELECT stored.*, identities.storage_order FROM (#{definition}) stored
        LEFT JOIN module_entry_identities identities ON identities.id = stored.id
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "List order is part of the dedicated storage contract; roll code forward"
  end
end
