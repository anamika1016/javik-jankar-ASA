# Cache dashboard aggregates and lightweight billing summaries. Each request
# checks source revisions, and
# fully scoped SQL is part of the key so filters and office access stay separate.
class DashboardSqlCache
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 16.megabytes)
  TABLES = %w[afls target_mappings vrps module_records].freeze

  def source_revision
    revision
  end

  def select_all(sql)
    key = ["jj-dashboard-aggregates-v1", revision, Digest::SHA256.hexdigest(sql)]
    rows = DashboardCacheFill.synchronize(key) do
      STORE.fetch(key, expires_in: 2.minutes) do
        ActiveRecord::Base.connection.select_all(sql).to_a
      end
    end
    rows.deep_dup
  end

  private

  def revision
    @revision ||= begin
      expressions = TABLES.flat_map do |table|
        ["(SELECT COUNT(*) FROM #{table}) AS #{table}_count",
         "(SELECT COALESCE(MAX(updated_at)::text, '') FROM #{table}) AS #{table}_updated"]
      end
      ActiveRecord::Base.connection.select_one("SELECT #{expressions.join(', ')}").values.join("/")
    end
  end
end
