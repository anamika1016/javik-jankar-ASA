# The one place that answers "give me the LG Directory rows for these module
# slugs", backed by the lg_* tables instead of module_records.
#
# Why this exists: reading these masters out of module_records means loading
# every row for the slug, parsing its JSON payload and filtering in Ruby.
# Building one village dropdown loads 4,153 records at ~73ms, and a
# registration form builds five of them. The lg_* tables hold the same rows
# with the payload lifted into indexed columns, so the same answer costs a
# couple of milliseconds.
#
# What this deliberately does NOT do is reinterpret the data. Rows come back
# responding to `id` and `data` exactly like a ModuleRecord, in the same order,
# already filtered by the same active predicate -- so every label-derivation
# rule downstream (the gram panchayat name/code swap, the code-like-value
# checks, the per-slug field aliases) keeps running unchanged on the same
# payloads. Callers should see no difference beyond speed.
class LgDirectory
  MODELS = [LgState, LgDistrict, LgBlock, LgGramPanchayat, LgVillage].freeze

  SLUG_MODELS = MODELS.each_with_object({}) do |model, map|
    model::MODULE_SLUGS.each { |slug| map[slug] = model }
  end.freeze

  SLUGS = SLUG_MODELS.keys.freeze

  class << self
    # True when every slug asked for lives in these tables. Mixed requests fall
    # back to module_records so a caller combining an LG master with some other
    # module still gets one coherent list.
    def covers?(slugs)
      list = Array(slugs).map(&:to_s)
      list.any? && list.all? { |slug| SLUGS.include?(slug) }
    end

    # Active rows for the given slug(s), newest first -- the same rows, in the
    # same order that the legacy generic-record query plus the Ruby
    # active_module_record? filter produced.
    def records_for(slugs)
      requested = Array(slugs).map(&:to_s)
      return [] if requested.empty?

      by_model = requested.group_by { |slug| SLUG_MODELS[slug] }
      rows = by_model.flat_map do |model, model_slugs|
        next [] if model.nil?

        model.active.for_slug(model_slugs).catalogue_order.to_a
      end
      # Several models in one call still have to come back in one newest-first
      # order, the way a single module_records query would have returned them.
      return rows if by_model.size <= 1

      rows.sort_by { |row| [-row.created_at.to_f, -row.id] }
    end

    # Dropdown pairs straight off the indexed columns, for the common case of
    # one level named by its own column. Returns [[label, id], ...] newest
    # first; callers still apply their own uniq/sort.
    def option_pairs(slug)
      model = SLUG_MODELS[slug.to_s]
      return [] unless model

      model.active.for_slug(slug.to_s).catalogue_order.pluck(model.name_column, :id)
    end

    def model_for(slug)
      SLUG_MODELS[slug.to_s]
    end

    # ── Keeping the mirror in step ──────────────────────────────────────────
    #
    # There is a database trigger (jj_lg_directory_sync) that does this too,
    # and it is the better hook because it catches bulk and raw-SQL writes.
    # But db/schema.rb cannot represent triggers, so any database built with
    # db:schema:load -- the test database, a freshly provisioned environment --
    # comes up without it. Correctness therefore cannot rest on the trigger
    # alone, so the same upsert is available here and is driven from a
    # ModuleRecord callback. Both are idempotent, so running both is harmless.

    # Maintenance re-derives columns from current dedicated data, never from
    # the retained archive. Ordinary imports already run the BEFORE triggers.
    def sync!(ids)
      MODELS.each { |model| model.where(id: Array(ids)).update_all("data = data") }
    end

    def resync!(slugs = SLUGS)
      Array(slugs).group_by { |slug| SLUG_MODELS[slug] }.each do |model, source_slugs|
        model&.for_slug(source_slugs)&.update_all("data = data")
      end
    end

    def derived_column_mismatch_count(model)
      comparisons = LgDirectoryColumns::ALIASES.map do |column, aliases|
        "#{model.connection.quote_column_name(column)} IS DISTINCT FROM COALESCE(#{aliases.map { |key| "NULLIF(data ->> '#{key}', '')" }.join(', ')})"
      end
      comparisons << "status IS DISTINCT FROM (data ->> 'status')"
      comparisons << "active IS DISTINCT FROM (#{LgDirectoryColumns::ACTIVE_SQL.gsub('payload ->>', 'data ->>')})"
      model.where(comparisons.join(' OR ')).count
    end

    private

    # Guard for boot order and for deploys where the migration has not run yet:
    # every caller falls back to module_records when this is false.
    def ready?
      return @ready if defined?(@ready) && !Rails.env.development?

      @ready = MODELS.all? { |model| model.table_exists? }
    rescue StandardError
      @ready = false
    end
  end
end
