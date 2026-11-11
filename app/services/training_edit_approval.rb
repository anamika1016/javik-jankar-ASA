require "base64"

# Revisions remain separate from live training data until the responsible Agronomist approves.
class TrainingEditApproval
  SLUG = "training-form-edit-request".freeze
  PHOTO_VIEW_FIELDS = {
    "photo_front_view" => "Photo Front View",
    "photo_back_view" => "Photo Back View",
    "photo_close_up_view" => "Photo Close-up View",
    "photo_long_shot" => "Photo Long Shot"
  }.freeze
  IMAGE_KEYS = (%w[training_register_upload training_photo_upload_with_geo_tag] + PHOTO_VIEW_FIELDS.keys).freeze
  class InvalidTransition < StandardError; end
  REVISION_READ_CACHE = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
  REVISION_SHARED_CACHE = ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp/cache/training-revisions"))

  # Only the latest revision controls billing; untouched records remain eligible.
  def self.unapproved_record_ids
    # Revision JSON contains before/proposed snapshots and uploaded evidence.
    # Check tuple versions without reading those TOAST payloads on every page.
    # ctid also changes on a second update in the same transaction, where xmin
    # and a manually preserved updated_at alone would miss the change.
    scope = ModuleRecord.where(module_slug: SLUG)
    version_sql = "MD5(COALESCE(STRING_AGG(id::text || ':' || xmin::text || ':' || ctid::text, ',' ORDER BY id), ''))"
    version = scope.pick(Arel.sql(version_sql))
    prefix = ["training-unapproved-v2", ModuleRecord.connection_pool.db_config.database]
    key = [*prefix, version]
    DashboardCacheFill.synchronize(key) do
      cached = REVISION_READ_CACHE.read(key)
      next cached unless cached.nil?

      # Puma workers have separate local stores. Reuse a version-matched result
      # from another worker instead of parsing the same large snapshots again.
      shared = shared_revision_cache(:read, key)
      if shared.is_a?(Array) && shared.all? { |id| id.is_a?(String) }
        REVISION_READ_CACHE.write(key, shared, expires_in: 10.minutes)
        next shared
      end

      # The version and IDs below share one SQL snapshot. A concurrent write
      # between the probe and this read must never cache new IDs under an old
      # version (a different transaction may still see that old version).
      rows = read_unapproved_revision_rows(scope.select(Arel.sql(version_sql)).to_sql)
      actual_version = rows.first&.last || "d41d8cd98f00b204e9800998ecf8427e"
      ids = rows.filter_map do |record_id, status, _|
        record_id = record_id.to_s
        record_id if record_id.present? && status != "Approved"
      end
      actual_key = [*prefix, actual_version]
      REVISION_READ_CACHE.write(actual_key, ids, expires_in: 10.minutes)
      # Version checks, not this retention period, control freshness. Retain
      # the shared result across local-cache expiry and worker restarts.
      shared_revision_cache(:write, actual_key, ids, expires_in: 1.day)
      ids
    end.dup
  end

  def self.shared_revision_cache(operation, key, ids = nil, **options)
    # Same-host Puma workers share this small file without requiring a second
    # database. Keep one slot per database, not an accumulating file per version.
    store = Rails.env.test? ? Rails.cache : REVISION_SHARED_CACHE
    slot = key.first(2)
    if operation == :read
      entry = store.read(slot)
      entry[:ids] if entry.is_a?(Hash) && entry[:version] == key.last
    else
      store.write(slot, { version: key.last, ids: ids }, **options)
    end
  rescue StandardError => error
    # Shared caching is optional. Preserve the existing database read if its
    # cache backend is unavailable; never make an approval decision from a TTL.
    Rails.logger.warn("Training revision cache #{operation} unavailable: #{error.class}")
    nil
  end

  def self.read_unapproved_revision_rows(version_query)
    # Keep the newest-revision-wins rule in PostgreSQL. Read scalar ID/status
    # pairs instead of instantiating each latest revision as an Active Record.
    ModuleRecord
      .where(module_slug: SLUG)
      .order(Arel.sql("(data::jsonb ->> 'record_id'), id DESC"))
      .pluck(
        Arel.sql("DISTINCT ON ((data::jsonb ->> 'record_id')) (data::jsonb ->> 'record_id')"),
        Arel.sql("data::jsonb ->> 'status'"),
        Arel.sql("(#{version_query})")
      )
  end

  def self.identity(actor)
    "#{actor['record_type'].presence || 'User'}:#{actor['id']}"
  end

  def self.username(value)
    value.to_s.sub(/\s*\([^)]*\)\s*\z/, "").gsub(/\s+/, " ").strip.downcase
  end

  # An approver may be stored by login, display name, or mobile; treat them all as the
  # same person so the current approver is recognised regardless of which form was saved.
  def self.actor_usernames(actor)
    [actor["username"], actor["user_name"], actor["name"], actor["mobile_no"]]
      .compact_blank.map { |value| username(value) }.uniq
  end

  # Who owns the Jeevika Jankar this training belongs to. The portal shows
  # this as "Transfer By", falling back to "Registered By" when the Jeevika
  # Jankar has never been transferred, and that owner is who an edit goes to.
  #
  # This replaces routing by "the one Agronomist on the FCO office", which
  # broke as soon as an office had two Agronomists covering different TOs --
  # a normal arrangement, and no reason to block an edit.
  def self.training_vrp(data)
    vrp_id = data.values_at("jeevika_jankar_id", "vrp_id", "select_vrp").find(&:present?)
    return if vrp_id.blank?

    Vrp.find_by(id: vrp_id)
  end

  # "Transfer By" lives on the jeevika-jankar-transfer records, keyed by the
  # Jeevika Jankar id trailing each saved label.
  def self.transfer_owner_username(vrp)
    return if vrp.blank?

    ModuleRecord.where(module_slug: "jeevika-jankar-transfer")
      .order(updated_at: :desc, id: :desc)
      .find_each do |record|
        data = record.data
        next if %w[deleted is_deleted discarded].any? { |key| %w[1 true yes deleted].include?(data[key].to_s.downcase) }
        next unless data["status"].blank? || data["status"].to_s.casecmp("Active").zero?
        next unless Array(data["jeevika_jankar_names"]).any? { |label| label.to_s[/-\s*(\d+)\s*\z/, 1] == vrp.id.to_s }

        return data["user_name"].to_s.sub(/\s*\([^)]*\)\s*\z/, "").strip.presence
      end
    nil
  end

  def self.catalogue_entry(catalogue, record_type:, id:)
    catalogue.find do |entry|
      entry["record_type"].to_s == record_type.to_s && entry["id"].to_s == id.to_s
    end
  end

  def self.catalogue_entry_by_username(catalogue, name)
    wanted = username(name)
    return if wanted.blank?

    catalogue.find do |entry|
      [entry["user_name"], entry["username"], TrainingStaffScope.name(entry)]
        .compact_blank.any? { |value| username(value) == wanted }
    end
  end

  # The owner of the Jeevika Jankar, as an approver entry, or nil.
  def self.owner_approver(data, staff_catalogue: nil)
    vrp = training_vrp(data)
    return if vrp.blank?

    catalogue = staff_catalogue || TrainingStaffScope.staff_catalogue
    transferred = transfer_owner_username(vrp)
    if transferred.present?
      entry = catalogue_entry_by_username(catalogue, transferred)
      return entry if entry
    end

    return if vrp.created_by_id.blank? || vrp.created_by_type.blank?

    catalogue_entry(catalogue, record_type: vrp.created_by_type, id: vrp.created_by_id)
  end

  # The office, every Agronomist on it, and the ones who could actually
  # approve this edit (its own author cannot approve it).
  def self.approver_candidates(data, actor, staff_catalogue: nil)
    office = TrainingStaffScope.office_for(data, actor)
    assigned = TrainingStaffScope.staff(office, :agronomist, catalogue: staff_catalogue)
      .reject { |candidate| candidate["user_name"].blank? }
      .uniq { |candidate| username(candidate["user_name"]) }

    [office, assigned, assigned.reject { |candidate| identity(candidate) == identity(actor) }]
  end

  # Routing needs exactly one eligible Agronomist, and it can fail for three
  # different reasons. Saying only "assign one" sent people off to add a
  # second Agronomist when the real problem was that there were already two.
  def self.routing_error(data, actor, staff_catalogue: nil)
    # Nothing to explain when routing works. Asking the question this way
    # also keeps the message and the actual decision from drifting apart.
    return if automatic_routing(data, actor, staff_catalogue: staff_catalogue).present?

    owner = owner_approver(data, staff_catalogue: staff_catalogue)
    if owner && identity(owner) == identity(actor)
      return "This training's Jeevika Jankar is registered to you, and an edit cannot be approved " \
             "by its own author. Ask another user to submit this change."
    end

    office, assigned, eligible = approver_candidates(data, actor, staff_catalogue: staff_catalogue)
    if training_vrp(data).present?
      return "This training's Jeevika Jankar has no \"Registered By\" or \"Transfer By\" user on record, " \
             "so there is nobody to send the edit to. Set one on the Jeevika Jankar List."
    end

    place = office.presence ? "FCO office \"#{office}\"" : "this training's FCO office"
    if assigned.empty?
      "No active Agronomist account is assigned to #{place}. " \
        "Assign one in User List before submitting the edit."
    elsif eligible.empty?
      "You are the only Agronomist assigned to #{place}, and an edit cannot be approved by its own author. " \
        "Another active Agronomist must be assigned to that office."
    else
      names = eligible.map { |candidate| TrainingStaffScope.name(candidate) }.compact_blank.sort.join(", ")
      "#{eligible.size} active Agronomist accounts are assigned to #{place} (#{names}). " \
        "Exactly one is needed so the approval has a single owner -- deactivate or move the others."
    end
  end

  def self.automatic_routing(data, actor, staff_catalogue: nil)
    # The Jeevika Jankar's own owner comes first: it is a single, named person
    # whoever else works that office. Only when the training cannot be traced
    # back to a Jeevika Jankar does this fall back to the office Agronomist.
    owner = owner_approver(data, staff_catalogue: staff_catalogue)
    if owner && identity(owner) != identity(actor)
      return { "approvers" => [TrainingStaffScope.name(owner)],
               "approver_identities" => [identity(owner)],
               "approval_office" => TrainingStaffScope.office_for(data, actor),
               "approval_role" => "jeevika_jankar_owner" }
    end

    office, _assigned, candidates = approver_candidates(data, actor, staff_catalogue: staff_catalogue)
    return {} unless candidates.one?

    approver = candidates.first
    { "approvers" => [TrainingStaffScope.name(approver)],
      "approver_identities" => [identity(approver)], "approval_office" => office, "approval_role" => "agronomist" }
  end

  # Can we prove the Agronomist this request was routed to is no longer on
  # that office? Only a proven answer reroutes; "cannot tell" leaves the
  # request alone. Older requests were routed by name with no identity or
  # office stored, and treating those as stale unassigned healthy requests.
  #
  # Checked against the stored approval_office rather than rederiving it, so
  # a list page costs no extra query per row.
  def self.approver_stale?(revision, staff_catalogue: nil)
    identities = Array(revision.data["approver_identities"]).compact_blank
    office = revision.data["approval_office"]
    return false if identities.empty? || office.blank?

    current = TrainingStaffScope.staff(office, :agronomist, catalogue: staff_catalogue)
      .map { |candidate| identity(candidate) }
    identities.any? { |stored| current.exclude?(stored) }
  end

  def self.assign_automatic_approver!(revision, staff_catalogue: nil)
    return revision unless revision.data["status"] == "Pending"
    # Requests already routed to a valid Agronomist stay put. One whose
    # Agronomist has since been deactivated or moved off the office is
    # rerouted -- otherwise replacing an Agronomist stranded every request
    # that was already waiting with the old one.
    if revision.data["approval_role"] == "agronomist" &&
       !approver_stale?(revision, staff_catalogue: staff_catalogue)
      return revision
    end

    revision.with_lock do
      data = revision.data.deep_dup
      routing = automatic_routing(data["before"] || {}, data["requester"] || {}, staff_catalogue: staff_catalogue)
      routing = { "approvers" => [], "approver_identities" => [], "approval_role" => nil } if routing.empty?
      updated_data = data.merge(routing).merge("step" => 0)
      # Legacy unassigned requests are rechecked so a later Agronomist assignment
      # is still picked up. Skip the identical write/reload on every page render.
      next revision if updated_data == data

      # Who a request is waiting on is worth a trail; it changes who may act.
      if data["approvers"].present? && data["approvers"] != updated_data["approvers"]
        updated_data["history"] = Array(data["history"]) + [{
          "action" => "reassigned", "at" => Time.current.iso8601,
          "from" => Array(data["approvers"]).join(", "),
          "to" => Array(updated_data["approvers"]).join(", ").presence || "unassigned"
        }]
      end

      revision.update!(data: updated_data)
    end
    revision.reload
  end

  def self.submit!(record:, proposed:, actor:)
    record.with_lock do
      pending = ModuleRecord.where(module_slug: SLUG).where("data::jsonb ->> 'record_id' = ? AND data::jsonb ->> 'status' = 'Pending'", record.id.to_s).first
      if pending && pending.data["requester_identity"] != identity(actor)
        raise InvalidTransition, "Another user's edit is pending approval for this training form."
      end
      routing = automatic_routing(record.data, actor)
      raise InvalidTransition, routing_error(record.data, actor) if routing.empty?
      IMAGE_KEYS.each { |key| proposed[key] = (Array(record.data[key]) + Array(proposed[key])).compact_blank.uniq }
      # Preserve creator/ownership fields; CC edits cannot reassign records.
      record.data.each { |key, value| proposed[key] = value if key.start_with?("created_by") || %w[vrp_id select_vrp jeevika_jankar_id].include?(key) }
      if pending
        pending.with_lock do
          raise InvalidTransition, "This request was already decided. Reload the training form before editing." unless pending.data["status"] == "Pending"
          raise InvalidTransition, "The original record changed. Reload before submitting." unless comparable_data(pending.data["before"]) == comparable_data(record.data)
          previous = pending.data.deep_dup
          history = Array(previous["history"]) + [{ "action" => "resubmitted", "actor" => identity(actor), "at" => Time.current.iso8601 }]
          pending.update!(data: previous.merge(routing).merge(
            "proposed" => proposed, "step" => 0, "history" => history,
            "evidence" => (Array(previous["evidence"]) + evidence(record.data, proposed)).uniq
          ))
        end
        return pending
      end
      ModuleRecord.create!(module_slug: SLUG, data: {
        "record_id" => record.id, "before" => record.data.deep_dup, "proposed" => proposed,
        "requester" => actor.slice("id", "record_type", "username", "user_name", "name", "stakeholder", *TrainingStaffScope::OFFICE_KEYS),
        "requester_identity" => identity(actor), "status" => "Pending", "step" => 0,
        "history" => [], "evidence" => evidence(record.data, proposed)
      }.merge(routing))
    end
  end

  def self.edit_data(record, actor)
    return record.data unless record.module_slug == "training-form"

    revision = ModuleRecord.where(module_slug: SLUG)
      .where("data::jsonb ->> 'record_id' = ? AND data::jsonb ->> 'status' = 'Pending'", record.id.to_s).first
    return record.data unless revision && revision.data["requester_identity"] == identity(actor)

    revision.data["proposed"].deep_dup
  end

  def self.evidence(*snapshots)
    snapshots.flat_map { |data| IMAGE_KEYS.flat_map { |key| Array(data[key]) } }.compact_blank.uniq.filter_map do |url|
      next unless url.is_a?(String) && url.start_with?("/uploads/module_records/")
      path = Rails.root.join("public", url.delete_prefix("/"))
      root = Rails.root.join("public/uploads/module_records")
      next unless root.directory? && path.file? && path.realpath.to_s.start_with?("#{root.realpath}/")
      { "url" => url, "filename" => path.basename.to_s, "base64" => Base64.strict_encode64(path.binread) }
    end
  end

  def self.pending_for(actor)
    return [] if actor.blank?

    # The sidebar checks all pending revisions. Reuse one catalogue for this request
    # instead of loading every User and new-user record once per revision.
    staff_catalogue = TrainingStaffScope.staff_catalogue
    ModuleRecord.where(module_slug: SLUG).where("data::jsonb ->> 'status' = 'Pending'").order(id: :desc).select do |revision|
      assign_automatic_approver!(revision, staff_catalogue: staff_catalogue)
      visible?(revision, actor)
    end
  end

  # Lists and badges need routing metadata, not image evidence or training snapshots.
  # Projected revisions are read-only; routing and decisions use complete records.
  def self.summary_scope(scope = ModuleRecord.where(module_slug: SLUG))
    scope.select(:id, :module_slug, :created_at, :updated_at)
      .select("(module_records.data::jsonb - ARRAY['before', 'proposed', 'evidence', 'history'])::text AS data")
      .readonly
  end

  def self.summaries_for(actor, pending_only: false)
    return [] if actor.blank?

    scope = ModuleRecord.where(module_slug: SLUG)
    scope = scope.where("data::jsonb ->> 'status' = 'Pending'") if pending_only
    staff_catalogue = nil
    summary_scope(scope).order(id: :desc).filter_map do |summary|
      if summary.data["status"] == "Pending" && summary.data["approval_role"] != "agronomist"
        # Preserve legacy routing, loading staff once only when routing is needed.
        staff_catalogue ||= TrainingStaffScope.staff_catalogue
        revision = ModuleRecord.find(summary.id)
        assign_automatic_approver!(revision, staff_catalogue: staff_catalogue)
        summary.data = revision.data.except("before", "proposed", "evidence", "history")
      end
      summary if visible?(summary, actor)
    end
  end

  def self.visible?(revision, actor)
    return true if actor["user_type"].to_s.casecmp("admin").zero? || revision.data["requester_identity"] == identity(actor)

    if revision.data["approver_identities"].present?
      return Array(revision.data["approver_identities"]).include?(identity(actor))
    end
    aliases = actor_usernames(actor)
    Array(revision.data["approvers"]).any? { |label| aliases.include?(username(label)) }
  end

  def self.can_decide?(revision, actor)
    return false unless revision.data["status"] == "Pending" && Array(revision.data["approvers"]).any?
    return true if actor["user_type"].to_s.casecmp("admin").zero?

    if revision.data["approver_identities"].present?
      return revision.data["approver_identities"][revision.data["step"].to_i] == identity(actor)
    end
    approver = revision.data["approvers"][revision.data["step"].to_i]
    actor_usernames(actor).include?(username(approver))
  end

  # The "before" snapshot and the live record store the same values in different
  # shapes: blank as nil or "", a single upload as "path" or ["path"], and keys
  # that only appear once a newer form version saves them. Comparing raw hashes
  # therefore rejects approvals where nothing actually changed, so compare a
  # normalised view instead. Real content edits still differ and are still caught.
  def self.comparable_data(data)
    Hash(data).each_with_object({}) do |(key, value), memo|
      normalized = comparable_value(value)
      memo[key] = normalized unless normalized.nil?
    end
  end

  def self.comparable_value(value)
    case value
    when String
      value.strip.presence
    when Array
      cleaned = value.filter_map { |item| comparable_value(item) }
      # A single upload is stored as "path" in one snapshot and ["path"] in the
      # other, so collapse one-element arrays to make those two forms equal.
      cleaned.size == 1 ? cleaned.first : cleaned.presence
    when Hash
      comparable_data(value).presence
    else
      value
    end
  end

  # Apply only the requested changes to the latest record. A later unrelated
  # edit must not block approval or be overwritten by the old proposed snapshot.
  def self.merge_approved_data(before:, proposed:, current:)
    before, proposed, current = [before, proposed, current].map { |value| Hash(value) }
    keys = before.keys | proposed.keys
    # Email is stamped/backfilled on save, not an editable training field.
    # Keep the current email even for old pending snapshots lacking that key.
    changed = keys.reject { |key| key == "created_by_email" }
      .select { |key| comparable_value(before[key]) != comparable_value(proposed[key]) }
    protected_keys = (before.keys | current.keys).select do |key|
      (key.start_with?("created_by") && key != "created_by_email") ||
        (%w[vrp_id select_vrp jeevika_jankar_id fco_name trainee_department] + TrainingStaffScope::OFFICE_KEYS).include?(key)
    end
    conflicts = changed.select do |key|
      live = comparable_value(current[key])
      live != comparable_value(before[key]) && live != comparable_value(proposed[key])
    end
    # Ownership/office changes can invalidate the saved approval routing.
    conflicts |= protected_keys.select { |key| comparable_value(current[key]) != comparable_value(before[key]) }
    if conflicts.any?
      raise InvalidTransition, "These training fields changed after this request: #{conflicts.sort.join(', ')}. Reject this request and submit a fresh edit."
    end

    current.deep_dup.tap do |merged|
      changed.each do |key|
        proposed.key?(key) ? merged[key] = proposed[key].deep_dup : merged.delete(key)
      end
    end
  end

  def self.status_label(revision)
    status = revision.data["status"].to_s
    return "Approved" if status == "Approved"
    return "Rejected" if status == "Rejected"

    approver = Array(revision.data["approvers"])[revision.data["step"].to_i]
    approver.present? ? "Pending at #{approver}" : "Pending - Agronomist assignment unavailable"
  end

  def self.decide!(revision:, actor:, decision:, remarks:)
    assign_automatic_approver!(revision)
    raise InvalidTransition, "Invalid decision." unless %w[approve reject route].include?(decision)
    revision.with_lock do
      data = revision.data.deep_dup
      if decision == "route"
        raise InvalidTransition, "Only admin can route an unassigned pending request." unless actor["user_type"].to_s.casecmp("admin").zero? && data["status"] == "Pending" && Array(data["approvers"]).empty?
        routing = automatic_routing(data["before"] || {}, data["requester"] || {})
        raise InvalidTransition, routing_error(data["before"] || {}, data["requester"] || {}) if routing.empty?
        data.merge!(routing)
      else
        raise InvalidTransition, "This request is not awaiting your approval." unless can_decide?(revision, actor)
        raise InvalidTransition, "Remarks are required." if remarks.blank?
        if decision == "reject"
          data["status"] = "Rejected"
        else
          data["step"] = data["step"].to_i + 1
          if data["step"] >= data["approvers"].size
            record = ModuleRecord.find(data["record_id"])
            record.with_lock do
              raise InvalidTransition, "The original record is no longer a training form." unless record.module_slug == "training-form"
              merged = merge_approved_data(before: data["before"], proposed: data["proposed"], current: record.data)
              record.update!(data: merged)
            end
            data["status"] = "Approved"
          end
        end
      end
      data["history"] << { "action" => decision, "actor" => identity(actor), "remarks" => remarks, "at" => Time.current.iso8601 }
      revision.update!(data: data)
    end
  end
end
