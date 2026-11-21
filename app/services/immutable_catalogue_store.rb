require "objspace"

# For read-only catalogue snapshots only. Consumers copy values before editing
# them. Unlike MemoryStore's default Marshal coder, hits do not rebuild every
# string/hash/array. Account for the retained object graph, not just wire bytes.
class ImmutableCatalogueStore < ActiveSupport::Cache::MemoryStore
  class SnapshotEntry < ActiveSupport::Cache::Entry
    def initialize(value, retained_bytes:, **options)
      super(value, **options)
      @retained_bytes = retained_bytes
    end

    def bytesize
      @retained_bytes
    end
  end

  def initialize(options = {})
    super(options.merge(coder: nil, compress: false))
  end

  private

  def serialize_entry(entry, **)
    bytes = freeze_and_measure(entry.value, {})
    SnapshotEntry.new(entry.value, retained_bytes: bytes, expires_at: entry.expires_at, version: entry.version)
  end

  def freeze_and_measure(value, seen)
    return 0 if seen.key?(value.object_id)

    seen[value.object_id] = true
    bytes = ObjectSpace.memsize_of(value)
    bytes = [bytes, value.bytesize + 40].max if value.is_a?(String)
    case value
    when Hash
      value.each { |key, item| bytes += freeze_and_measure(key, seen) + freeze_and_measure(item, seen) }
    when Array
      value.each { |item| bytes += freeze_and_measure(item, seen) }
    end
    value.freeze
    bytes
  end
end
