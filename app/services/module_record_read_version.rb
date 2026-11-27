require "digest"

# Small transactional source stamps replace O(number of records) fingerprint
# scans on warm requests. Missing migration/triggers retain the old read path.
class ModuleRecordReadVersion
  TABLE = "module_record_read_versions".freeze
  # These are installed on every dedicated source table by
  # ActivateDedicatedModuleStorage.  They are deliberately table-level
  # triggers: module_records is archive-only and is not part of the read
  # readiness contract.
  TRIGGERS = %w[insert update delete truncate].map { |event| "jj_module_entries_versions_#{event}" }.freeze

  def self.fetch(slugs: nil)
    read(slugs: slugs) || yield
  end

  def self.read(slugs: nil, dependencies: [])
    pool = ModuleEntry.connection_pool
    return unless pool.schema_cache.data_source_exists?(TABLE)

    return unless storage_triggers_installed?
    return unless dependency_triggers_installed?(dependencies)

    # Global readers inspect the small set of module stamps, avoiding one
    # globally locked counter row that would serialize unrelated module writes.
    keys = slugs.nil? ? nil : Array(slugs).map { |slug| "module:#{slug}" }.uniq.sort
    ModuleEntry.uncached(dirties: false) do
      pool.with_connection do
        dependency_keys = dependencies.map { |table| "table:#{table}" }
        version_scope = ModuleRecordReadVersionRecord.all
        version_scope = if keys
          version_scope.where(source_key: ["epoch", *keys, *dependency_keys])
        else
          table = ModuleRecordReadVersionRecord.arel_table
          version_scope.where(source_key: "epoch").or(version_scope.where(table[:source_key].matches("module:%")))
            .or(version_scope.where(source_key: dependency_keys))
        end
        # This is an ordinary application read, so keep it entirely in Active
        # Record/Arel rather than building a SELECT statement by hand.
        values = version_scope
          .order(:source_key)
          .pluck(:source_key, :revision)
          .to_h
        return unless values.key?("epoch")

        selected = (keys || values.keys.reject { |key| key == 'epoch' }.sort)
          .map { |key| [key, values.fetch(key, 0)] }
        "clock-v1:#{values.fetch('epoch')}:#{Digest::SHA256.hexdigest(selected.to_json)}"
      end
    end
  end
  def self.storage_triggers_installed?
    connection = ModuleEntry.connection
    return false unless ModuleEntry.connection_pool.schema_cache.data_source_exists?("module_entry_sources")
    connection.select_value(<<~SQL.squish)
      SELECT COUNT(*) = 4 * (SELECT COUNT(DISTINCT table_name) FROM module_entry_sources)
      FROM pg_trigger WHERE tgrelid IN (SELECT to_regclass(table_name) FROM module_entry_sources)
        AND tgname IN (#{TRIGGERS.map { |name| connection.quote(name) }.join(', ')})
        AND tgenabled IN ('O','A') AND NOT tgisinternal
    SQL
  rescue StandardError
    false
  end

  def self.dependency_triggers_installed?(tables)
    return true if tables.empty?

    connection = ModuleEntry.connection
    names = tables.map { |table| connection.quote(table) }.join(',')
    connection.select_value(<<~SQL.squish).to_i == tables.uniq.size
      SELECT COUNT(*) FROM pg_trigger
      WHERE tgrelid IN (SELECT to_regclass(name) FROM unnest(ARRAY[#{names}]::text[]) AS name)
        AND tgname = 'jj_module_entry_dependency_changed' AND tgenabled IN ('O','A') AND NOT tgisinternal
    SQL
  rescue StandardError
    false
  end
end
