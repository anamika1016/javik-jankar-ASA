require "digest"
require "monitor"

# Bound lock memory while coalescing simultaneous cold-cache requests in a Puma
# worker. Rails.cache remains authoritative, including its existing TTL/version.
class DashboardCacheFill
  LOCKS = Array.new(64) { Monitor.new }.freeze

  def self.synchronize(key)
    # A summary can fill a nested participation cache. Do not acquire a second
    # stripe while holding the first (two summaries could acquire in reverse).
    return yield if Thread.current[:dashboard_cache_fill_active]

    index = Digest::SHA256.hexdigest(key.to_s).to_i(16) % LOCKS.size
    LOCKS[index].synchronize do
      Thread.current[:dashboard_cache_fill_active] = true
      begin
        yield
      ensure
        Thread.current[:dashboard_cache_fill_active] = nil
      end
    end
  end
end
