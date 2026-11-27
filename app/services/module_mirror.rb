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

  class << self
    def covers?(slug)
      SLUG_MODELS.key?(slug.to_s) && ready?
    end

    def partition(slugs)
      Array(slugs).map(&:to_s).uniq.partition { |slug| covers?(slug) }
    end

    def model_for(slug) = SLUG_MODELS[slug.to_s]

    def read_scope(slugs)
      requested = Array(slugs).map(&:to_s)
      scope = if requested.any? && requested.all? { |slug| SLUG_MODELS.key?(slug) }
        ModuleEntry.from("module_entry_payloads AS module_entries")
      else
        ModuleEntry.all
      end
      scope.where(module_slug: slugs).readonly
    end

    def projection_scope(active_only: false)
      scope = ModuleEntry.from("module_entry_payloads AS module_entries").readonly
      active_only ? scope.where("catalogue_active = TRUE") : scope
    end

    def relation_for(slug)
      model = model_for(slug)
      return ModuleEntry.where(module_slug: slug) unless model
      model.respond_to?(:for_slug) ? model.for_slug(slug.to_s) : model.all
    end

    def records_for(slugs)
      projection_scope.where(module_slug: slugs).where("record_active = TRUE").catalogue_order.map do |row|
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

    def reset_ready!
      remove_instance_variable(:@ready) if defined?(@ready)
    end

  end
end
