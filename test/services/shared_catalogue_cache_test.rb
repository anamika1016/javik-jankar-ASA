require "test_helper"
require "tmpdir"

class SharedCatalogueCacheTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("shared-catalogue-test-")
    @shared = SharedCatalogueCache.new(@directory)
  end
  teardown { FileUtils.remove_entry(@directory) }

  test "separate worker stores reuse identical data without sharing mutable payloads" do
    key = ["test-catalogue", "v1"]
    value = CatalogueReadCache.fetch(ActiveSupport::Cache::MemoryStore.new, key,
      version: "v1", current_version: -> { "v1" }, shared: @shared) { { rows: [String.new("Original")] } }
    value[:rows].first.replace("Changed by caller")
    actual = CatalogueReadCache.fetch(ActiveSupport::Cache::MemoryStore.new, key,
      version: "v1", current_version: -> { raise "Shared hit must not rebuild/probe" }, shared: @shared) { raise "Rebuilt" }
    assert_equal({ rows: ["Original"] }, actual)
  end

  test "source changes replace the slot and concurrent changes publish nothing" do
    first = ["test-catalogue", "v1"]
    second = ["test-catalogue", "v2"]
    @shared.write(first, "Before", expires_in: 1.hour)
    assert_nil @shared.read(second)
    memory = ActiveSupport::Cache::MemoryStore.new
    actual = CatalogueReadCache.fetch(memory, second,
      version: "v2", current_version: -> { "v3" }, shared: @shared) { "Changed concurrently" }
    assert_equal "Changed concurrently", actual
    assert_nil memory.read(second)
    assert_nil @shared.read(second)
    assert_equal "Before", @shared.read(first)
    @shared.write(second, "After", expires_in: 1.hour)
    assert_nil @shared.read(first)
    assert_equal "After", @shared.read(second)
    assert_equal 1, Dir.glob(File.join(@directory, "**/*")).count { |path| File.file?(path) && !path.end_with?(".lock") }
  end

  test "expired shared values are not reused" do
    key = ["test-expiry", "v1"]
    @shared.write(key, "Before", expires_in: 1.second)
    travel 2.seconds do
      assert_nil @shared.read(key)
    end
  end

  test "ordinary RAM expiry reuses shared data but never skips source invalidation" do
    memory = ActiveSupport::Cache::MemoryStore.new
    CatalogueReadCache.fetch(memory, ["test-ram-expiry", "v1"],
      version: "v1", current_version: -> { "v1" }, shared: @shared) { "Before" }
    travel 2.hours do
      assert_equal "Before", CatalogueReadCache.fetch(memory, ["test-ram-expiry", "v1"],
        version: "v1", current_version: -> { "v1" }, shared: @shared) { raise "Rebuilt unchanged data" }
      assert_equal "After", CatalogueReadCache.fetch(memory, ["test-ram-expiry", "v2"],
        version: "v2", current_version: -> { "v2" }, shared: @shared) { "After" }
    end
  end

  test "deploys invalidate derived values without accumulating a slot per code version" do
    key = ["test-deploy", "same-data-revision"]
    @shared.write(key, "Old implementation", expires_in: 1.hour)
    next_release = SharedCatalogueCache.new(@directory)
    next_release.define_singleton_method(:code_namespace) { "new-implementation" }
    assert_nil next_release.read(key)
    next_release.write(key, "New implementation", expires_in: 1.hour)
    assert_equal "New implementation", next_release.read(key)
    assert_nil @shared.read(key)
    assert_equal 1, Dir.glob(File.join(@directory, "**/*")).count { |path| File.file?(path) }
  end

  test "an unavailable cache lock falls back once and does not swallow builder errors" do
    blocked = File.join(@directory, "not-a-directory")
    File.write(blocked, "x")
    shared = SharedCatalogueCache.new(blocked)
    calls = 0
    assert_equal "Uncached", shared.synchronize(["test", "v1"]) { calls += 1; "Uncached" }
    assert_equal 1, calls
    assert_raises(Errno::ENOENT) do
      @shared.synchronize(["test", "v1"]) { raise Errno::ENOENT, "builder failed" }
    end
  end

  test "separate processes coalesce one cold shared fill" do
    skip "fork unavailable" unless Process.respond_to?(:fork)
    key = ["test-process-lock", "v1"]
    marker = File.join(@directory, "build-count")
    reader, writer = IO.pipe
    children = 2.times.map do
      fork do
        writer.close
        reader.read(1)
        shared = SharedCatalogueCache.new(@directory)
        shared.synchronize(key) do
          if shared.read(key).nil?
            File.open(marker, "a") { |file| file.puts "build" }
            sleep 0.03
            shared.write(key, "One build", expires_in: 1.hour)
          end
        end
        exit! 0
      end
    end
    reader.close
    writer.write("xx")
    writer.close
    children.each { |pid| Process.wait(pid); assert_predicate $?, :success? }
    assert_equal ["build"], File.readlines(marker, chomp: true)
    assert_equal "One build", @shared.read(key)
  end
end
