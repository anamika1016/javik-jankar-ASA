# Read projections belong here so lists can avoid loading large JSON payloads
# before the controller has applied the current user's visibility rules.
class ModuleRecordReadQuery
  def self.training_list_candidates(scope)
    omitted_keys = TrainingEditApproval::IMAGE_KEYS + %w[farmer_ids selected_farmer_ids farmers farmer_details]
    quoted_keys = omitted_keys.map { |key| ModuleRecord.connection.quote(key) }.join(",")
    scope.select(:id, :module_slug, :created_at, :updated_at)
      .select("(data::jsonb - ARRAY[#{quoted_keys}])::text AS data")
      .order(created_at: :desc)
  end

  # Dashboard and bill progress calculations inspect only the identifiers,
  # status and training labels below. Training records can additionally hold
  # multiple uploaded photos/documents; loading those JSON values for every
  # monthly calculation creates needless database transfer and Ruby GC work.
  # Return the same records with precisely the fields read by the progress
  # matcher, preserving all completion and approval decisions.
  def self.training_progress_records(scope)
    keys = %w[
      month training_month training_date selected_farmer_ids
      target_mapping_ids target_mapping_id
      ics_block ics gram_name village training_location training_method
      main_activities main_activity training_topic
      sub_activities sub_activity training_subject
      jeevika_jankar_id vrp_id select_vrp vrp_name jeevika_jankar_name
      trainer_contact trainer_name department trainee_department
      status approval_status approval_state deleted is_deleted discarded record_state
    ]
    quoted_keys = keys.map { |key| ModuleRecord.connection.quote(key) }.join(",")
    projection = <<~SQL.squish
      (SELECT COALESCE(jsonb_object_agg(field.key, field.value), '{}'::jsonb)
       FROM jsonb_each(COALESCE(module_records.data::jsonb, '{}'::jsonb)) AS field(key, value)
       WHERE field.key IN (#{quoted_keys}))::text AS data
    SQL

    scope.select(:id, :module_slug, :created_at, :updated_at).select(projection)
  end

  def self.latest_training_revision_summaries(record_ids: nil)
    scope = ModuleRecord.where(module_slug: TrainingEditApproval::SLUG)
    scope = scope.where("data::jsonb ->> 'record_id' IN (?)", record_ids) if record_ids.present?
    # The existing (record_id, id DESC) partial index supports latest-wins.
    # Project large JSON summaries only after choosing each latest revision.
    latest_ids = scope.select("DISTINCT ON ((data::jsonb ->> 'record_id')) id")
      .order(Arel.sql("(data::jsonb ->> 'record_id'), id DESC"))
    TrainingEditApproval.summary_scope(ModuleRecord.where(id: latest_ids))
  end

  def self.without_unapproved_training_records(scope, blocked_ids)
    # id::text preserves exact legacy reference matching (including leading
    # zeros/non-numeric references) without PostgreSQL integer coercion.
    ids = blocked_ids.select { |id| id.is_a?(String) }
    ids.empty? ? scope : scope.where.not("module_records.id::text IN (?)", ids)
  end

  def self.hydrate(records)
    return [] if records.empty?

    by_id = ModuleRecord.where(id: records.map(&:id)).index_by(&:id)
    records.filter_map { |record| by_id[record.id] }
  end

  def self.selected_location_records(row_tokens, allowed_slugs:)
    tokens = Array(row_tokens).filter_map do |token|
      slug, id = token.to_s.split(":", 2)
      [slug, id] if allowed_slugs.include?(slug) && id.present?
    end.uniq
    return [] if tokens.empty?

    # Preserve token order, reject wrong-slug IDs, and fetch the selection once.
    by_token = ModuleRecord.where(id: tokens.map(&:last), module_slug: tokens.map(&:first).uniq)
      .index_by { |record| [record.module_slug, record.id.to_s] }
    tokens.filter_map { |slug, id| by_token[[slug, id.to_i.to_s]] }.uniq
  end
end
