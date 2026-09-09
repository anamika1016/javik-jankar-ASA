require "base64"

# Revisions remain separate from live training data until the complete channel approves.
class TrainingEditApproval
  SLUG = "training-form-edit-request".freeze
  IMAGE_KEYS = %w[training_register_upload training_photo_upload_with_geo_tag].freeze
  class InvalidTransition < StandardError; end

  # Only the latest revision controls billing; untouched records remain eligible.
  def self.unapproved_record_ids
    latest = ModuleRecord.where(module_slug: SLUG).order(id: :desc)
    latest.each_with_object({}) { |revision, index| index[revision.data["record_id"].to_s] ||= revision.data["status"] }
      .select { |_id, status| status != "Approved" }.keys
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

  def self.channel(actor)
    # Approval Form may save either the account username or the display name.
    # Treat all identity fields as aliases for the same CC user.
    labels = [actor["username"], actor["user_name"], actor["name"], actor["mobile_no"]]
      .compact_blank.map { |value| username(value) }
    ModuleRecord.where(module_slug: "approval-master").select do |record|
      data = record.data
      data["module_name"] == "Training Form Edit" && data["status"].to_s.casecmp("Active").zero? &&
        labels.include?(username(data["user_name"])) &&
        (data["stakeholder_name"].blank? || data["stakeholder_name"].to_s.casecmp(actor["stakeholder"].to_s).zero?)
    end.sort_by { |record| [record.data["approval_level"].to_s[/\d+/].to_i, record.id] }
      .filter_map { |record| record.data["approver_approved_by"].presence }
  end

  def self.assign_configured_channel!(revision)
    return revision unless revision.data["status"] == "Pending" && Array(revision.data["approvers"]).empty?

    revision.with_lock do
      data = revision.data.deep_dup
      approvers = channel(data["requester"] || {})
      revision.update!(data: data.merge("approvers" => approvers)) if approvers.any?
    end
    revision.reload
  end

  def self.submit!(record:, proposed:, actor:)
    record.with_lock do
      pending = ModuleRecord.where(module_slug: SLUG).where("data::jsonb ->> 'record_id' = ? AND data::jsonb ->> 'status' = 'Pending'", record.id.to_s).exists?
      raise InvalidTransition, "This training form already has a pending edit request." if pending
      IMAGE_KEYS.each { |key| proposed[key] = (Array(record.data[key]) + Array(proposed[key])).compact_blank.uniq }
      # Preserve creator/ownership fields; CC edits cannot reassign records.
      record.data.each { |key, value| proposed[key] = value if key.start_with?("created_by") || %w[vrp_id select_vrp jeevika_jankar_id].include?(key) }
      ModuleRecord.create!(module_slug: SLUG, data: {
        "record_id" => record.id, "before" => record.data.deep_dup, "proposed" => proposed,
        "requester" => actor.slice("id", "record_type", "username", "user_name", "name", "mobile_no", "stakeholder"),
        "requester_identity" => identity(actor), "status" => "Pending", "step" => 0,
        "approvers" => channel(actor), "history" => [], "evidence" => evidence(record.data, proposed)
      })
    end
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

  def self.visible?(revision, actor)
    return true if actor["user_type"].to_s.casecmp("admin").zero? || revision.data["requester_identity"] == identity(actor)

    aliases = actor_usernames(actor)
    Array(revision.data["approvers"]).any? { |label| aliases.include?(username(label)) }
  end

  def self.can_decide?(revision, actor)
    return false unless revision.data["status"] == "Pending" && Array(revision.data["approvers"]).any?
    return true if actor["user_type"].to_s.casecmp("admin").zero?

    approver = revision.data["approvers"][revision.data["step"].to_i]
    actor_usernames(actor).include?(username(approver))
  end

  def self.status_label(revision)
    status = revision.data["status"].to_s
    return "Approved" if status == "Approved"
    return "Returned" if %w[Rejected Returned].include?(status)

    approver = Array(revision.data["approvers"])[revision.data["step"].to_i]
    approver.present? ? "Pending at #{approver}" : "Pending - approval channel not configured"
  end

  def self.decide!(revision:, actor:, decision:, remarks:)
    raise InvalidTransition, "Invalid decision." unless %w[approve reject route].include?(decision)
    revision.with_lock do
      data = revision.data.deep_dup
      if decision == "route"
        raise InvalidTransition, "Only admin can route an unassigned pending request." unless actor["user_type"].to_s.casecmp("admin").zero? && data["status"] == "Pending" && Array(data["approvers"]).empty?
        data["approvers"] = channel(data["requester"])
        raise InvalidTransition, "Configure a Training Form Edit approval channel for this requester first." if data["approvers"].empty?
      else
        raise InvalidTransition, "This request is not awaiting your approval." unless can_decide?(revision, actor)
        raise InvalidTransition, "Remarks are required." if remarks.blank?
        if decision == "reject"
          data["status"] = "Returned"
        else
          data["step"] = data["step"].to_i + 1
          if data["step"] >= data["approvers"].size
            record = ModuleRecord.find(data["record_id"])
            record.with_lock do
              raise InvalidTransition, "The original record changed. Reject this request and submit a fresh edit." unless record.module_slug == "training-form" && record.data == data["before"]
              record.update!(data: data["proposed"])
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
