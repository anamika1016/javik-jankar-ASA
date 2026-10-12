class AddDashboardRevisionIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # DashboardSqlCache checks MAX(updated_at) separately from COUNT(*).
    # These indexes let PostgreSQL read the latest timestamp without scanning
    # every row. The slug prefix also supports billing's activity revision check.
    %i[afls vrps module_records].each do |table|
      add_index table, :updated_at, order: :desc,
        name: "index_#{table}_on_updated_at", algorithm: :concurrently, if_not_exists: true
    end
    add_index :module_records, [:module_slug, :updated_at], order: { updated_at: :desc },
      name: "index_module_records_on_slug_and_updated_at", algorithm: :concurrently, if_not_exists: true
  end
end
