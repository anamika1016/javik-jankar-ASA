require "test_helper"

class CatalogueReadCacheTest < ActiveSupport::TestCase
  # A second connection must see the committed source row, not a fixture
  # transaction. Only the row created below is removed during cleanup.
  self.use_transactional_tests = false

  test "cold fill detects another connection's write even with Rails query caching enabled" do
    record = ModuleRecord.create!(module_slug: "catalogue-cache-concurrency-test", data: { "label" => "Before" })
    cache = ActiveSupport::Cache::MemoryStore.new
    reader = -> { ModuleRecord.where(id: record.id).pick(:data) }
    ActiveRecord::Base.cache do
      version = reader.call
      result = CatalogueReadCache.fetch(cache, "test-version", version: version, current_version: reader) do
        Thread.new do
          ModuleRecord.connection_pool.with_connection do
            ModuleRecord.where(id: record.id).update_all(data: { "label" => "After" })
          end
        end.value
        # Establish that this connection's SQL cache still contains the old
        # probe. The final guard must bypass it to detect the external commit.
        assert_equal version, reader.call
        "New payload"
      end
      assert_equal "New payload", result
      assert_nil cache.read("test-version"), "New data must not be cached under the old version"
    end
  ensure
    ModuleRecord.where(id: record.id).delete_all if record
  end
end
