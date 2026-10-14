# Cache dashboard aggregates and lightweight billing summaries. Each request
# checks source revisions, and
# fully scoped SQL is part of the key so filters and office access stay separate.
class DashboardSqlCache
  # Production uses Solid Cache on its dedicated cache database.  Keeping this
  # aggregate cache in a per-worker MemoryStore makes every Puma worker execute
  # the same expensive dashboard query after expiry.  Share it through the
  # configured Rails cache instead.  The in-memory store is retained in test so
  # cache behaviour remains isolated and deterministic there.
  STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new(size: 16.megabytes) : Rails.cache
  TABLES = %w[afls target_mappings vrps module_records].freeze

  def source_revision
    revision
  end

  def select_all(sql)
    key = ["jj-dashboard-aggregates-v2", revision, Digest::SHA256.hexdigest(sql)]
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
