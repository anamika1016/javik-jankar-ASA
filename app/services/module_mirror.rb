# Compatibility readers over authoritative dedicated tables. No source-table
# fallback: the retained ModuleRecord model is archival code only.
class ModuleMirror
  Row = Struct.new(:id, :module_slug, :data, :created_at, :updated_at)
  MODELS = [
    LgState, LgDistrict, LgBlock, LgGramPanchayat, LgVillage,
    ModuleMonth, ModuleStakeholder, ModuleStakeholderRole, ModuleRole,
    ModuleParentOffice, ModuleOfficeCategory, ModuleSubOffice,
    ModuleProject, ModuleMainActivity, ModuleSubActivity,
    ModuleJjTransfer, ModuleUserHierarchy, ModuleAccessControl,
    ModuleVrpType, ModuleApproval, ModuleTraining, ModuleOtherTarget,
    ModuleOtherFarmerTarget, ModuleBill, ModulePaymentDetail
  ].freeze

  SLUG_MODELS = MODELS.each_with_object({}) do |model, map|
    slugs = model.respond_to?(:module_slug) ? [model.module_slug] : model::MODULE_SLUGS
    Array(slugs).each { |slug| map[slug] = model }
  end.freeze

  SLUGS = SLUG_MODELS.keys.freeze
  @route_cache = nil

  class << self
    def covers?(slug)
      dedicated_table_for(slug).present?
    end

    def partition(slugs)
      Array(slugs).map(&:to_s).uniq.partition { |slug| covers?(slug) }
    end

    def model_for(slug) = SLUG_MODELS[slug.to_s]

    def dedicated_table_for(slug)
      return unless ready?

      routes = @route_cache ||= ModuleEntry.connection.select_rows("SELECT slug, table_name FROM module_entry_sources").to_h
      table = routes[slug.to_s]
      table if table.present? && table != "module_records"
    rescue StandardError
      nil
    end

    def find_by_id(id)
      records_by_id([id]).first
    end

    def records_by_id(ids)
      ids = Array(ids).compact.uniq
      return [] if ids.empty?
      return ModuleEntry.where(id: ids).to_a unless ready?

      connection = ModuleEntry.connection
      quoted_ids = ids.map { |id| connection.quote(id) }.join(", ")
      slugs = connection.select_values(
        "SELECT DISTINCT module_slug FROM module_entry_identities WHERE id IN (#{quoted_ids})"
      )
      return ModuleEntry.where(id: ids).to_a if slugs.empty?

      read_scope(slugs).where(id: ids).to_a
    end

    def read_scope(slugs)
      requested = Array(slugs).map(&:to_s).uniq
      mirrored, legacy = partition(requested)
      sources = []
      sources << dedicated_projection_sql(mirrored) if mirrored.any?
      sources << legacy_projection_sql(legacy) if legacy.any?
      return ModuleEntry.none if sources.empty?

      ModuleEntry.from("(#{sources.join(' UNION ALL ')}) AS module_entries")
        .where(module_slug: requested).readonly
    end

    def projection_scope(active_only: false, slugs: nil)
      requested = Array(slugs).map(&:to_s).uniq
      sources = if requested.empty?
        ["SELECT id, module_slug, data, created_at, updated_at, catalogue_active, record_active FROM module_entry_payloads"]
      else
        mirrored, legacy = partition(requested)
        [].tap do |parts|
          parts << dedicated_projection_sql(mirrored) if mirrored.any?
          parts << legacy_projection_sql(legacy) if legacy.any?
        end
      end
      return ModuleEntry.none if sources.empty?

      scope = ModuleEntry.from("(#{sources.join(' UNION ALL ')}) AS module_entries").readonly
      scope = scope.where(module_slug: requested) if requested.any?
      active_only ? scope.where("catalogue_active = TRUE") : scope
    end

    def relation_for(slug)
      model = model_for(slug)
      return read_scope(slug) unless model
      model.respond_to?(:for_slug) ? model.for_slug(slug.to_s) : model.all
    end

    def records_for(slugs)
      projection_scope(slugs: slugs).where("record_active = TRUE").catalogue_order.map do |row|
        Row.new(row.id, row.module_slug, row.data, row.created_at, row.updated_at)
      end
    end

    def rows_for(slugs, order: :created_at)
      read_scope(slugs).order(order => :desc, id: :desc).map do |row|
        Row.new(row.id, row.module_slug, row.data, row.created_at, row.updated_at)
      end
    end

    def ready?
      return @ready if defined?(@ready)
      connection = ModuleEntry.connection
      @ready = connection.data_source_exists?("module_entries") &&
        connection.data_source_exists?("module_entry_payloads") && sync_triggers_installed?
    rescue StandardError
      @ready = false
    end

    def sync_triggers_installed?
      ModuleRecordReadVersion.storage_triggers_installed?
    end

    def sync_routes_installed? = ready?

    private

    # Build a small UNION from only the dedicated tables requested. The broad
    # compatibility view is useful for old callers, but even an optimizer can
    # spend time planning its dozens of branches on every hot dropdown/report.
    def dedicated_projection_sql(slugs)
      Array(slugs).group_by { |slug| dedicated_table_for(slug) }.filter_map do |table_name, model_slugs|
        next if table_name.blank?

        table = ModuleEntry.connection.quote_table_name(table_name)
        slug_sql = if model_slugs.one?
          ModuleEntry.connection.quote(model_slugs.first)
        else
          "source_slug"
        end
        <<~SQL.squish
          SELECT entries.id, #{slug_sql}::text AS module_slug, entries.data, entries.created_at, entries.updated_at,
            entries.catalogue_active, entries.active AS record_active, identities.storage_order
          FROM #{table} entries
          LEFT JOIN module_entry_identities identities ON identities.id = entries.id
        SQL
      end
    end

    def legacy_projection_sql(slugs)
      quoted_slugs = Array(slugs).map { |slug| ModuleEntry.connection.quote(slug) }.join(", ")
      <<~SQL.squish
        SELECT records.id, records.module_slug, records.data::jsonb AS data, records.created_at, records.updated_at,
          NOT (COALESCE(LOWER(BTRIM(records.data::jsonb ->> 'deleted')), '') IN ('1','true','yes','deleted')
            OR COALESCE(LOWER(BTRIM(records.data::jsonb ->> 'is_deleted')), '') IN ('1','true','yes','deleted')
            OR COALESCE(LOWER(BTRIM(records.data::jsonb ->> 'discarded')), '') IN ('1','true','yes','deleted')
            OR (COALESCE(BTRIM(records.data::jsonb ->> 'status'), '') <> '' AND LOWER(BTRIM(records.data::jsonb ->> 'status')) <> 'active')) AS catalogue_active,
          NOT (COALESCE(LOWER(BTRIM(records.data::jsonb ->> 'deleted')), '') IN ('1','true','yes','deleted')
            OR COALESCE(LOWER(BTRIM(records.data::jsonb ->> 'is_deleted')), '') IN ('1','true','yes','deleted')
            OR COALESCE(LOWER(BTRIM(records.data::jsonb ->> 'discarded')), '') IN ('1','true','yes','deleted')
            OR (COALESCE(BTRIM(records.data::jsonb ->> 'status'), '') <> '' AND LOWER(BTRIM(records.data::jsonb ->> 'status')) <> 'active')) AS record_active,
          identities.storage_order
        FROM module_records records
        LEFT JOIN module_entry_identities identities ON identities.id = records.id
        WHERE records.module_slug IN (#{quoted_slugs})
      SQL
    end

    def reset_ready!
      remove_instance_variable(:@ready) if defined?(@ready)
      remove_instance_variable(:@route_cache) if defined?(@route_cache)
    end

  end
end
