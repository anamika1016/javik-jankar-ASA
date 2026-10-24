require "test_helper"

# Several screens enrich themselves from asa.ploughmanagro.com inside a
# Rails.cache.fetch block, and those blocks bail out with
#   return [] unless response.is_a?(Net::HTTPSuccess)
#
# `return` inside a block leaves the enclosing *method*, so Rails.cache.fetch
# never gets a value to store. While the upstream is down or erroring, every
# request therefore pays the full connect+read timeout again rather than being
# answered from a cached miss.
#
# These tests pin the mechanism and the exposure, so the cost is measured
# rather than assumed.
class ExternalFetchCacheTest < ActiveSupport::TestCase
  CONTROLLER = Rails.root.join("app/controllers/target_mappings_controller.rb")

  # The test environment uses a null store, so these tests need a real one to
  # observe whether anything was written.
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  # Mirrors the shape of the real fetch helpers exactly.
  def fetch_with_return_in_block(key, succeed:)
    @calls += 1
    Rails.cache.fetch(key, expires_in: 10.minutes, skip_nil: true) do
      return [] unless succeed

      ["value"]
    end
  end

  test "a bail-out inside the cache block leaves nothing cached, so the work repeats" do
    @calls = 0
    results = 3.times.map { fetch_with_return_in_block("bail-out-key", succeed: false) }

    assert_equal [[], [], []], results
    assert_equal 3, @calls
    assert_nil Rails.cache.read("bail-out-key"),
      "the cache stayed empty, so a failing upstream is re-contacted on every request"
  end

  test "a value returned normally from the block is cached and reused" do
    @calls = 0
    results = 3.times.map { fetch_with_return_in_block("happy-key", succeed: true) }

    assert_equal [["value"], ["value"], ["value"]], results
    assert_equal ["value"], Rails.cache.read("happy-key")
  end

  test "the upstream helpers really do bail out with return inside the cache block" do
    source = File.read(CONTROLLER)
    bail_outs = source.scan(/return (?:\[\]|nil) unless response\.is_a\?\(Net::HTTPSuccess\)/).size

    assert_operator bail_outs, :>=, 4,
      "expected the upstream helpers to bail out this way; found #{bail_outs}"
    assert_includes source, "Rails.cache.fetch",
      "those bail-outs sit inside Rails.cache.fetch blocks, which is why the miss is never stored"
  end

  test "each upstream call can block a request for its connect plus read timeout" do
    source = File.read(CONTROLLER)
    timeouts = source.scan(/open_timeout:\s*(\d+),\s*read_timeout:\s*(\d+)/)

    assert_operator timeouts.size, :>=, 5,
      "expected several upstream calls guarded by explicit timeouts"
    worst = timeouts.map { |open, read| open.to_i + read.to_i }.max
    assert_operator worst, :<=, 20,
      "one upstream call can hold a request for #{worst} seconds"
  end
end
