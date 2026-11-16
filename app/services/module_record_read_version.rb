require "digest"

# Small transactional source stamps replace O(number of records) fingerprint
# scans on warm requests. Missing migration/triggers retain the old read path.
class ModuleRecordReadVersion
  TABLE = "module_record_read_versions".freeze
  TRIGGERS = %w[insert update delete truncate].map { |event| "jj_module_record_versions_#{event}" }.freeze

  def self.fetch(slugs: nil)
    read(slugs: slugs) || yield
  end

  def self.read(slugs: nil)
    pool = ModuleRecord.connection_pool
    return unless pool.schema_cache.data_source_exists?(TABLE)

    # Global readers inspect the small set of module stamps, avoiding one
    # globally locked counter row that would serialize unrelated module writes.
    keys = slugs.nil? ? nil : Array(slugs).map { |slug| "module:#{slug}" }.uniq.sort
    ModuleRecord.uncached(dirties: false) do
      pool.with_connection do |connection|
        # Verify enabled triggers in the same read. A schema-only restore, or
        # explicitly disabled triggers, must never make stale stamps trusted.
        trigger_names = TRIGGERS.map { |name| connection.quote(name) }.join(",")
        selection = if keys
          "source_key IN (#{(['epoch'] + keys).map { |key| connection.quote(key) }.join(',')})"
        else
          "(source_key = 'epoch' OR source_key LIKE 'module:%')"
        end
        rows = connection.select_rows(<<~SQL.squish)
          SELECT source_key, revision FROM #{TABLE}
          WHERE #{selection} AND
            (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'module_records'::regclass
             AND tgname IN (#{trigger_names}) AND tgenabled IN ('O', 'A') AND NOT tgisinternal) = 4
          ORDER BY source_key
        SQL
        values = rows.to_h
        return unless values.key?("epoch")

        selected = (keys || values.keys.reject { |key| key == 'epoch' }.sort)
          .map { |key| [key, values.fetch(key, 0)] }
        "clock-v1:#{values.fetch('epoch')}:#{Digest::SHA256.hexdigest(selected.to_json)}"
      end
    end
  end
end
