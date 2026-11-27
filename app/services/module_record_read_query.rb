# Read projections belong here so lists can avoid loading large JSON payloads
# before the controller has applied the current user's visibility rules.
class ModuleRecordReadQuery
  # Preserve JSON types and caller ordering without transferring unrelated
  # uploads/history or instantiating a model just to read dropdown fields.
  def self.field_value_rows(scope, keys)
    return [] if keys.empty?

    quoted_keys = keys.map { |key| ModuleEntry.connection.quote(key.to_s) }
    scope.pluck(Arel.sql("json_build_array(#{quoted_keys.map { |key| "data::jsonb -> #{key}" }.join(', ')})"))
  end

  def self.projected_data_rows(scope, keys)
    return [] if keys.empty?

    quoted_keys = keys.map { |key| ModuleEntry.connection.quote(key.to_s) }.join(", ")
    object = "CASE WHEN jsonb_typeof(data::jsonb) = 'object' THEN data::jsonb ELSE '{}'::jsonb END"
    projection = "(SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb) " \
      "FROM jsonb_each(#{object}) WHERE key IN (#{quoted_keys}))"
    scope.pluck(:id, Arel.sql(projection))
  end

  def self.admin_training_list_rows(scope, limit: 100)
    slug = ModuleEntry.connection.quote(TrainingEditApproval::SLUG)
    # Match the Ruby list key exactly: latest revision by ID, Pending first,
    # created_at floored to whole seconds (nil means epoch), then ID descending.
    # Training photo/participant JSON is never selected while ranking rows.
    pending = <<~SQL.squish
      CASE WHEN (
        SELECT revisions.data::jsonb ->> 'status' FROM module_entries revisions
        WHERE revisions.module_slug = #{slug}
          AND revisions.data::jsonb ->> 'record_id' = module_entries.id::text
        ORDER BY revisions.id DESC LIMIT 1
      ) = 'Pending' THEN 0 ELSE 1 END
    SQL
    summary = <<~SQL.squish
      (SELECT json_build_object(
        'id', revisions.id, 'module_slug', revisions.module_slug,
        'created_at', revisions.created_at, 'updated_at', revisions.updated_at,
        'data', (revisions.data::jsonb - ARRAY['before', 'proposed', 'evidence', 'history'])::text
      ) FROM module_entries revisions
       WHERE revisions.module_slug = #{slug}
         AND revisions.data::jsonb ->> 'record_id' = module_entries.id::text
       ORDER BY revisions.id DESC LIMIT 1)
    SQL
    # Read the selected summaries in the ranking statement's snapshot, so a
    # concurrent decision cannot change badges after pending ordering is set.
    scope.reorder(Arel.sql("#{pending}, COALESCE(FLOOR(EXTRACT(EPOCH FROM module_entries.created_at)), 0) DESC, module_entries.id DESC"))
      .limit(limit).pluck(:id, Arel.sql(summary))
  end

  def self.training_list_candidates(scope)
    omitted_keys = TrainingEditApproval::IMAGE_KEYS + %w[farmer_ids selected_farmer_ids farmers farmer_details]
    quoted_keys = omitted_keys.map { |key| ModuleEntry.connection.quote(key) }.join(",")
    scope.select(:id, :module_slug, :created_at, :updated_at)
      .select("(data::jsonb - ARRAY[#{quoted_keys}])::text AS data")
      .order(created_at: :desc)
  end

  # Dashboard and bill progress calculations inspect only the identifiers,
  # status and training labels below. Training records can additionally hold
  # multiple uploaded photos/documents; loading those JSON values for every
  # monthly calculation creates needless database transfer and Ruby GC work.
  # Removing those payloads directly is materially cheaper than rebuilding a
  # JSON object with jsonb_each/jsonb_object_agg for every training row. The
  # calculation receives the same fields it uses for completion and approval
  # decisions, while harmless legacy metadata remains available for fallback
  # readers.
  def self.training_progress_records(scope)
    omitted_keys = (TrainingEditApproval::IMAGE_KEYS + %w[attachment_upload field_photo farmer_details farmers]).uniq
    quoted_keys = omitted_keys.map { |key| ModuleEntry.connection.quote(key) }.join(",")
    projection = "(COALESCE(module_entries.data::jsonb, '{}'::jsonb) - ARRAY[#{quoted_keys}])::text AS data"

    scope.select(:id, :module_slug, :created_at, :updated_at).select(projection)
  end

  def self.latest_training_revision_summaries(record_ids: nil)
    if record_ids.present?
      # One indexed top-row lookup per requested training ID avoids sorting
      # every matching historical revision before selecting the latest IDs.
      ids = Array(record_ids).compact.uniq
      return TrainingEditApproval.summary_scope(ModuleEntry.none) if ids.empty?

      connection = ModuleEntry.connection
      values = ids.map { |id| "(#{connection.quote(id.to_s)}::text)" }.join(", ")
      slug = connection.quote(TrainingEditApproval::SLUG)
      latest_ids_sql = <<~SQL.squish
        SELECT latest.id FROM (VALUES #{values}) AS requested(record_id)
        CROSS JOIN LATERAL (
          SELECT revisions.id FROM module_entries AS revisions
          WHERE revisions.module_slug = #{slug}
            AND revisions.data::jsonb ->> 'record_id' = requested.record_id
          ORDER BY revisions.id DESC LIMIT 1
        ) AS latest
      SQL
      return TrainingEditApproval.summary_scope(ModuleEntry.where("module_entries.id IN (#{latest_ids_sql})"))
    end
    scope = ModuleEntry.where(module_slug: TrainingEditApproval::SLUG)
    scope = scope.where("data::jsonb ->> 'record_id' IN (?)", record_ids) if record_ids.present?
    # The existing (record_id, id DESC) partial index supports latest-wins.
    # Project large JSON summaries only after choosing each latest revision.
    latest_ids = scope.select("DISTINCT ON ((data::jsonb ->> 'record_id')) id")
      .order(Arel.sql("(data::jsonb ->> 'record_id'), id DESC"))
    TrainingEditApproval.summary_scope(ModuleEntry.where(id: latest_ids))
  end

  def self.without_unapproved_training_records(scope, blocked_ids)
    # id::text preserves exact legacy reference matching (including leading
    # zeros/non-numeric references) without PostgreSQL integer coercion.
    ids = blocked_ids.select { |id| id.is_a?(String) }
    ids.empty? ? scope : scope.where.not("module_entries.id::text IN (?)", ids)
  end

  def self.hydrate(records)
    return [] if records.empty?

    by_id = ModuleMirror.read_scope(records.map(&:module_slug)).where(id: records.map(&:id)).index_by(&:id)
    records.filter_map { |record| by_id[record.id] }
  end

  def self.selected_location_records(row_tokens, allowed_slugs:)
    tokens = Array(row_tokens).filter_map do |token|
      slug, id = token.to_s.split(":", 2)
      [slug, id] if allowed_slugs.include?(slug) && id.present?
    end.uniq
    return [] if tokens.empty?

    # Preserve token order, reject wrong-slug IDs, and fetch the selection once.
    by_token = ModuleMirror.read_scope(tokens.map(&:first).uniq)
      .where(id: tokens.map(&:last))
      .index_by { |record| [record.module_slug, record.id.to_s] }
    tokens.filter_map { |slug, id| by_token[[slug, id.to_i.to_s]] }.uniq
  end
end
