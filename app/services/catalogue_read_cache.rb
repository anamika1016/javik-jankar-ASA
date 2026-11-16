# A request may read its revision before another transaction changes a master.
# Never publish a newer payload under that older revision's key. Warm hits keep
# the existing single version probe; only cold fills need the second probe.
class CatalogueReadCache
  def self.fetch(cache, key, version:, current_version:, expires_in: 1.hour, shared: nil, shared_expires_in: 1.week, &builder)
    DashboardCacheFill.synchronize(key) do
      cached = cache.read(key)
      next cached unless cached.nil?

      fill = lambda do
        shared_value = shared&.read(key)
        unless shared_value.nil?
          cache.write(key, shared_value, expires_in: expires_in)
          next shared_value
        end
        value = builder.call
        # Another database connection cannot invalidate this request's SQL
        # query cache. The final probe must reach PostgreSQL, not reuse the
        # earlier version result after a concurrent commit.
        actual_version = ActiveRecord::Base.uncached(dirties: false) { current_version.call }
        if actual_version == version
          cache.write(key, value, expires_in: expires_in)
          # Live revisions and the code namespace control freshness. Keep the
          # single shared slot across ordinary RAM expiry/worker restarts.
          shared&.write(key, value, expires_in: shared_expires_in)
        end
        value
      end
      shared ? shared.synchronize(key, &fill) : fill.call
    end
  end
end
