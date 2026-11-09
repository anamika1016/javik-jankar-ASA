# Cache scalar dropdown reads without decoding unrelated training/photo JSON
# on every request. Tuple identity invalidates imports and direct edits too.
class ModuleFieldOptionsCache
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)

  def self.revision
    ModuleRecord.uncached(dirties: false) do
      ModuleRecord.pick(Arel.sql("MD5(COALESCE(STRING_AGG(id::text || ':' || xmin::text || ':' || ctid::text, ',' ORDER BY id), ''))"))
    end
  end

  def self.fetch(scope, fields)
    version = revision
    key = ["module-field-options-v1", ModuleRecord.connection_pool.db_config.database,
      scope.to_sql, fields, version]
    cache = Rails.env.test? ? Rails.cache : STORE
    CatalogueReadCache.fetch(cache, key, version: version, current_version: -> { revision }) { yield }.deep_dup
  end
end
