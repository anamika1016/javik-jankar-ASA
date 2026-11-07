# A request may read its revision before another transaction changes a master.
# Never publish a newer payload under that older revision's key. Warm hits keep
# the existing single version probe; only cold fills need the second probe.
class CatalogueReadCache
  def self.fetch(cache, key, version:, current_version:, expires_in: 1.hour)
    DashboardCacheFill.synchronize(key) do
      cached = cache.read(key)
      next cached unless cached.nil?

      value = yield
      # Another database connection cannot invalidate this request's SQL
      # query cache. The final probe must reach PostgreSQL, not reuse the
      # earlier version result after a concurrent commit.
      actual_version = ActiveRecord::Base.uncached(dirties: false) { current_version.call }
      cache.write(key, value, expires_in: expires_in) if actual_version == version
      value
    end
  end
end
