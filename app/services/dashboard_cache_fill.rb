require "digest"
require "monitor"

# Coalesce only simultaneous fills of the same cache key.  The former 64
# striped lock pool also serialized unrelated keys on a hash collision: a slow
# bill aggregate could therefore hold an interactive request for minutes and
# exhaust Puma's two web threads. Entries are reference-counted and removed
# after the final waiter leaves, so lock memory remains bounded by active work.
class DashboardCacheFill
  LockEntry = Struct.new(:lock, :users)
  REGISTRY_LOCK = Monitor.new
  LOCKS = {}

  def self.synchronize(key)
    # A summary can fill a nested participation cache. Do not acquire a second
    # stripe while holding the first (two summaries could acquire in reverse).
    return yield if Thread.current[:dashboard_cache_fill_active]

    lock_key = Digest::SHA256.hexdigest(Marshal.dump(key))
    entry = REGISTRY_LOCK.synchronize do
      current = LOCKS[lock_key] ||= LockEntry.new(Monitor.new, 0)
      current.users += 1
      current
    end

    entry.lock.synchronize do
      Thread.current[:dashboard_cache_fill_active] = true
      begin
        yield
      ensure
        Thread.current[:dashboard_cache_fill_active] = nil
      end
    end
  ensure
    if entry
      REGISTRY_LOCK.synchronize do
        entry.users -= 1
        LOCKS.delete(lock_key) if entry.users.zero? && LOCKS[lock_key].equal?(entry)
      end
    end
  end
end
