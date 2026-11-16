# Cache scalar dropdown reads without decoding unrelated training/photo JSON
# on every request. Tuple identity invalidates imports and direct edits too.
class ModuleFieldOptionsCache
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)

  def self.revision_scope(scope)
    # The payload retains its complete filter. Version all rows of the source
    # module, including inactive/deleted rows, so changing a filter field or
    # importing a newly eligible row invalidates without parsing JSON here.
    conditions = scope.where_values_hash
    conditions.key?("module_slug") ? ModuleRecord.where(module_slug: conditions["module_slug"]) : ModuleRecord.all
  end

  def self.revision(scope = ModuleRecord.all)
    ModuleRecord.uncached(dirties: false) do
      revision_scope(scope).pick(Arel.sql("MD5(COALESCE(STRING_AGG(id::text || ':' || xmin::text || ':' || ctid::text, ',' ORDER BY id), ''))"))
    end
  end

  def self.fetch(scope, fields, version: nil)
    version ||= revision(scope)
    key = ["module-field-options-v2", ModuleRecord.connection_pool.db_config.database,
      scope.to_sql, fields, version]
    cache = Rails.env.test? ? Rails.cache : STORE
    CatalogueReadCache.fetch(cache, key, version: version, current_version: -> { revision(scope) }) { yield }.deep_dup
  end
end
