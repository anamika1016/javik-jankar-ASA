# frozen_string_literal: true

# Shared VRP / Jeevika Jankar access, approval, and form-option helpers.
# Used by API v1 only so the web VrpsController stays untouched.
module VrpAccess
  extend ActiveSupport::Concern

  APPROVAL_REGISTRATION_MODULES = ["Farmer Registration", "VRP Registration", "Jeevika Jankar Registration"].freeze

  private

  def controller_current_user
    nil
  end

  def current_app_user_id
    current_app_user&.dig("id") || controller_current_user&.id
  end

  def current_app_user_ids
    ([current_app_user_id] + legacy_current_app_user_ids).compact.uniq
  end

  def legacy_current_app_user_ids
    return [] unless model_ready?(:ModuleRecord)

    username = current_app_user&.dig("username").to_s
    emails = current_app_user_emails
    return [] if username.blank? && emails.blank?

    ModuleRecord.where(module_slug: "new-user").select do |record|
      record.data["user_name"].to_s == username ||
        emails.include?(record.data["email"].to_s.strip.downcase)
    end.map(&:id)
  end

  def admin_user?
    current_app_user&.dig("user_type").to_s.casecmp("admin").zero?
  end

  def own_vrps
    return Vrp.all if current_app_user.blank? || admin_user?

    ids = current_app_user_ids
    emails = current_app_user_emails
    return Vrp.none if ids.blank? && emails.blank?

    scope = Vrp.none
    if ids.any?
      scope = scope.or(Vrp.where(created_by_id: ids))
      scope = scope.or(Vrp.where(user_id: ids)) if Vrp.column_names.include?("user_id")
    end

    if emails.any?
      unassigned_scope = Vrp.where(created_by_id: nil).where("LOWER(email) IN (?)", emails)
      unassigned_scope = unassigned_scope.where(user_id: nil) if Vrp.column_names.include?("user_id")
      scope = scope.or(unassigned_scope)
    end

    scope
  end

  def current_app_user_emails
    emails = [current_app_user&.dig("email")]

    if model_ready?(:User)
      user = User.find_by(user_name: current_app_user&.dig("username")) || User.find_by(id: current_app_user_id)
      emails << user&.email
    end

    emails.compact_blank.map { |email| email.to_s.strip.downcase }.uniq
  end

  def registered_by_name(vrp)
    creator = registered_by_user(vrp)
    return creator.full_name.presence || creator.user_name if creator.respond_to?(:full_name)

    if creator
      full_name = [creator.data["first_name"], creator.data["last_name"]].compact_blank.join(" ")
      return full_name.presence || creator.data["user_name"].presence
    end

    "Unknown"
  end

  def registered_by_user(vrp)
    @registered_by_user_cache ||= {}
    cache_key = vrp.id
    return @registered_by_user_cache[cache_key] if @registered_by_user_cache.key?(cache_key)

    if vrp.created_by_id.present?
      user = User.find_by(id: vrp.created_by_id) if model_ready?(:User)
      return @registered_by_user_cache[cache_key] = user if user

      record = ModuleRecord.find_by(id: vrp.created_by_id) if model_ready?(:ModuleRecord)
      return @registered_by_user_cache[cache_key] = record if record
    end

    if model_ready?(:User)
      user = User.find_by("LOWER(email) = ?", vrp.email.to_s.strip.downcase)
      return @registered_by_user_cache[cache_key] = user if user
    end

    return unless model_ready?(:ModuleRecord)

    @registered_by_user_cache[cache_key] = ModuleRecord.where(module_slug: "new-user")
      .where("LOWER(COALESCE(data->>'email', '')) = ?", vrp.email.to_s.strip.downcase)
      .order(created_at: :desc)
      .first
  end

  def visible_vrps
    return Vrp.all if current_app_user.blank? || admin_user?

    mapped_vrps = cluster_mapped_vrps.to_a
    base_vrps = if cluster_incharge_login? || mapped_vrps.any?
      mapped_vrps
    else
      own_vrps.to_a
    end

    (base_vrps + approval_related_vrps).uniq
  end

  def find_visible_vrp(id)
    visible_vrps.to_a.find { |vrp| vrp.id == id.to_i }
  end

  def find_manageable_vrp(id)
    own_vrps.find_by(id: id)
  end

  def cluster_mapped_vrps
    labels = current_cluster_incharge_labels
    return Vrp.none if labels.blank?

    Vrp.where.not(cluster_incharge: [nil, ""]).select do |vrp|
      labels.any? { |label| cluster_label_matches?(label, vrp.cluster_incharge) }
    end
  end

  def current_cluster_incharge_labels
    labels = [
      current_app_user&.dig("name"),
      current_app_user&.dig("username"),
      current_app_user&.dig("user_name")
    ]

    labels.concat(user_model_cluster_labels)
    labels.concat(legacy_user_cluster_labels)
    labels.compact_blank.uniq
  end

  def cluster_incharge_login?
    current_role = [
      current_app_user&.dig("role"),
      current_app_user&.dig("role_name")
    ].compact_blank.join(" ")
    return true if current_role.downcase.include?("cluster")

    hierarchy_cluster_incharge_labels.any? do |mapped_label|
      current_cluster_incharge_labels.any? { |current_label| cluster_label_matches?(mapped_label, current_label) }
    end
  end

  def user_model_cluster_labels
    return [] unless model_ready?(:User)

    user = User.find_by(user_name: current_app_user&.dig("username")) || User.find_by(id: current_app_user_id)
    return [] unless user

    [user.full_name, user.user_name]
  end

  def legacy_user_cluster_labels
    return [] unless model_ready?(:ModuleRecord)

    username = current_app_user&.dig("username").to_s
    return [] if username.blank?

    record = ModuleRecord
      .where(module_slug: "new-user")
      .order(created_at: :desc)
      .detect { |row| row.data["user_name"].to_s == username }
    return [] unless record

    full_name = [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence
    [full_name, record.data["user_name"], record.data["name"]]
  end

  def approval_queue
    scope = Vrp.all.select { |vrp| approval_visible_after_sent?(vrp) }
    return scope if admin_user?

    scope.select { |vrp| current_user_in_approval_channel?(vrp) }
  end

  def approvable_vrps
    Vrp.all.select { |vrp| approval_pending_for_action?(vrp) && current_user_can_approve?(vrp) }
  end

  def approval_related_vrps
    Vrp.all.select do |vrp|
      approval_visible_after_sent?(vrp) && current_user_in_approval_channel?(vrp)
    end
  end

  def approval_visible_after_sent?(vrp)
    approval_sent?(vrp) || vrp.status.to_i >= 25 || [55, 99].include?(vrp.status.to_i)
  end

  def approval_pending_for_action?(vrp)
    !(
      [55, 99].include?(vrp.status.to_i) ||
        approval_complete?(vrp) ||
        approval_rejected?(vrp) ||
        vrp.status.to_i < 25 ||
        (vrp.status.to_i == 25 && !approval_sent?(vrp))
    )
  end

  def current_user_can_approve?(vrp)
    step = current_approval_step(vrp)
    return false unless step
    return false if approval_step_closed?(vrp, step)

    approver_matches_current_user?(step.data["approver_approved_by"].to_s) ||
      approver_matches_current_user?(approval_approver_name(step))
  end

  def current_user_in_approval_channel?(vrp)
    approval_steps_for(vrp).any? { |step| approval_step_matches_current_user?(step) } ||
      approval_history_for(vrp).any? { |record| approval_history_matches_current_user?(record) }
  end

  def approval_step_matches_current_user?(step)
    approver_matches_current_user?(step.data["approver_approved_by"].to_s) ||
      approver_matches_current_user?(approval_approver_name(step))
  end

  def approval_history_matches_current_user?(record)
    approver_matches_current_user?(record.data["approver"].to_s) ||
      approver_matches_current_user?(record.data["action_by"].to_s)
  end

  def approval_display_step(vrp)
    current_approval_step(vrp) ||
      approval_steps_for(vrp).reverse.find { |step| approval_step_closed?(vrp, step) } ||
      approval_steps_for(vrp).last
  end

  def current_approval_step(vrp)
    sequence = current_approval_sequence(vrp)
    approval_steps_for(vrp).find { |record| approval_sequence(record) == sequence }
  end

  def current_approval_sequence(vrp)
    return nil if [55, 99].include?(vrp.status.to_i) || approval_rejected?(vrp)
    return nil unless approval_sent?(vrp)

    approval_steps_for(vrp)
      .find { |step| !approval_step_closed?(vrp, step) }
      &.then { |step| approval_sequence(step) }
  end

  def next_approval_sequence(vrp)
    sequence = current_approval_sequence(vrp).to_i
    approved_sequences = approved_approval_sequences(vrp)

    approval_steps_for(vrp)
      .select { |record| approval_sequence(record) > sequence }
      .find { |step| !approved_sequences.include?(approval_sequence(step)) && !approval_step_closed?(vrp, step) }
      &.then { |step| approval_sequence(step) }
  end

  def approval_steps_for(vrp)
    return [] unless model_ready?(:ModuleRecord)

    @approval_steps_for_cache ||= {}
    cache_key = vrp.id
    return @approval_steps_for_cache[cache_key] if @approval_steps_for_cache.key?(cache_key)

    creator_identities = vrp_creator_identities(vrp)
    return @approval_steps_for_cache[cache_key] = [] if creator_identities.blank?

    matching_records = ModuleRecord
      .where(module_slug: "approval-master")
      .order(created_at: :asc)
      .select do |record|
        record_stakeholder = record.data["stakeholder_name"].to_s
        record_vrp_name = record.data["vrp_name"].to_s

        active_module_record?(record) &&
          approval_registration_module?(record.data["module_name"]) &&
          vrp_name_matches?(record_vrp_name, vrp) &&
          creator_identities.any? do |identity|
            module_value_matches?(record_stakeholder, identity[:stakeholder]) &&
              approval_identity_filters_match?(record, identity)
          end
      end

    matching_records
      .group_by { |record| approval_sequence(record) }
      .values
      .map { |records| records.max_by { |record| approval_record_priority(record) } }
      .sort_by { |record| approval_sequence(record) }

    @approval_steps_for_cache[cache_key] = matching_records
  end

  def approval_sequence(record)
    approval_sequence_from_level(record.data["approval_level"])
  end

  def approval_sequence_from_level(level)
    normalized = level.to_s.downcase.gsub(/\s+/, " ").strip
    approval_ordinals.each do |label, sequence|
      return sequence if normalized.include?(label)
    end

    normalized[/\b(?:approval|level|lvl|l)\s*[-#:]?\s*(\d+)\b/, 1].to_i.presence ||
      normalized[/\A\s*(\d+)(?:st|nd|rd|th)?\s*(?:approval)?\s*\z/, 1].to_i.presence ||
      normalized[/\b(\d+)(?:st|nd|rd|th)?\s+approval\b/, 1].to_i.presence ||
      1
  end

  def approval_ordinals
    {
      "first" => 1,
      "1st" => 1,
      "frist" => 1,
      "second" => 2,
      "2nd" => 2,
      "secound" => 2,
      "seconed" => 2,
      "third" => 3,
      "3rd" => 3,
      "thrid" => 3,
      "fourth" => 4,
      "4th" => 4,
      "forth" => 4,
      "fifth" => 5,
      "5th" => 5,
      "sixth" => 6,
      "6th" => 6,
      "seventh" => 7,
      "7th" => 7,
      "eighth" => 8,
      "8th" => 8,
      "ninth" => 9,
      "9th" => 9,
      "tenth" => 10,
      "10th" => 10
    }
  end

  def approver_labels
    name = current_app_user&.dig("name").to_s
    username = current_app_user&.dig("username").to_s
    role = current_app_user&.dig("role").to_s
    office = current_app_user&.dig("office").to_s

    labels = [
      name,
      username,
      role.present? && name.present? ? "#{name} (#{role})" : nil,
      role.present? && username.present? ? "#{username} (#{role})" : nil,
      office.present? && name.present? ? "#{name} (#{office})" : nil
    ]
    labels.concat(user_model_approver_labels)
    labels.concat(legacy_user_approver_labels)

    labels
      .compact_blank
      .uniq
  end

  def user_model_approver_labels
    return [] unless model_ready?(:User)

    user = User.find_by(user_name: current_app_user&.dig("username")) || User.find_by(id: current_app_user_id)
    return [] unless user

    full_name = user.full_name.presence
    [
      full_name,
      user.user_name,
      user.role.present? && full_name.present? ? "#{full_name} (#{user.role})" : nil,
      user.role.present? && user.user_name.present? ? "#{user.user_name} (#{user.role})" : nil,
      user.office.present? && full_name.present? ? "#{full_name} (#{user.office})" : nil
    ]
  end

  def legacy_user_approver_labels
    return [] unless model_ready?(:ModuleRecord)

    username = current_app_user&.dig("username").to_s
    return [] if username.blank?

    record = ModuleRecord
      .where(module_slug: "new-user")
      .order(created_at: :desc)
      .detect { |row| row.data["user_name"].to_s == username }
    return [] unless record

    full_name = [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence
    role = record.data["role"].presence
    office = record.data["office"].presence
    [
      full_name,
      record.data["user_name"].presence,
      role.present? && full_name.present? ? "#{full_name} (#{role})" : nil,
      role.present? && record.data["user_name"].present? ? "#{record.data["user_name"]} (#{role})" : nil,
      office.present? && full_name.present? ? "#{full_name} (#{office})" : nil
    ]
  end

  def approver_matches_current_user?(approver)
    return false if approver.to_s.strip.blank?

    normalized_approver = normalize_approver_label(approver)

    approver_labels.any? do |label|
      normalized_label = normalize_approver_label(label)
      approver.to_s == label.to_s ||
        normalized_approver == normalized_label ||
        normalized_approver.include?(normalized_label) ||
        normalized_label.include?(normalized_approver)
    end
  end

  def normalize_approver_label(label)
    label.to_s.sub(/\s*\([^)]*\)\s*\z/, "").strip.downcase
  end

  def cluster_label_matches?(expected, actual)
    expected_values = cluster_label_match_values(expected)
    actual_values = cluster_label_match_values(actual)
    return false if expected_values.blank? || actual_values.blank?
    return true if (expected_values & actual_values).any?

    expected_values.any? do |expected_value|
      actual_values.any? { |actual_value| similar_person_label?(expected_value, actual_value) }
    end
  end

  def cluster_label_match_values(label)
    base = label.to_s.sub(/\s*\([^)]*\)\s*\z/, "")
    [label, base].map { |value| normalize_person_label(value) }.reject { |value| value.blank? || value.length < 3 }.uniq
  end

  def normalize_person_label(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def similar_person_label?(left, right)
    left_words = left.split
    right_words = right.split
    return false unless left_words.size == right_words.size
    return false if left_words.size < 2
    return false unless left_words.last == right_words.last

    left_words.zip(right_words).all? { |left_word, right_word| left_word == right_word || one_edit_apart?(left_word, right_word) }
  end

  def one_edit_apart?(left, right)
    return false if left.blank? || right.blank?
    return false if (left.length - right.length).abs > 1

    longer, shorter = [left, right].sort_by(&:length).reverse
    edits = 0
    longer_index = 0
    shorter_index = 0

    while longer_index < longer.length && shorter_index < shorter.length
      if longer[longer_index] == shorter[shorter_index]
        longer_index += 1
        shorter_index += 1
      else
        edits += 1
        return false if edits > 1

        longer_index += 1
        shorter_index += 1 if longer.length == shorter.length
      end
    end

    edits + (longer.length - longer_index) <= 1
  end

  def module_value_matches?(expected, actual)
    return true if expected.blank?

    normalize_approver_label(expected).casecmp(normalize_approver_label(actual)).zero?
  end

  def approval_registration_module?(module_name)
    module_name.blank? || APPROVAL_REGISTRATION_MODULES.any? { |name| module_value_matches?(module_name, name) }
  end

  def approval_office_matches?(expected, actual)
    expected.blank? || actual.blank? || module_value_matches?(expected, actual)
  end

  def approval_identity_filters_match?(record, identity)
    approval_office_matches?(approval_record_office(record), identity[:office]) &&
      approval_office_matches?(record.data["office_category"], identity[:office_category]) &&
      approval_user_name_matches?(record.data["user_name"], identity_user_name_values(identity))
  end

  def approval_record_office(record)
    record.data["sub_office_name"].presence || record.data["office"]
  end

  def approval_user_name_matches?(expected, actual)
    return true if expected.blank?

    Array(actual).compact_blank.any? { |value| module_value_matches?(expected, value) }
  end

  def identity_user_name_values(identity)
    (Array(identity[:user_names]) + [identity[:user_name]]).compact_blank.uniq
  end

  def vrp_name_matches?(expected, vrp)
    return true if expected.blank?

    [vrp_approval_label(vrp), vrp.name].compact.any? { |label| module_value_matches?(expected, label) }
  end

  def vrp_approval_label(vrp)
    [vrp.name.presence, vrp.mobile_no.presence].compact.join(" - ").presence
  end

  def approval_record_priority(record)
    [(record.data["user_name"].present? || record.data["vrp_name"].present?) ? 1 : 0, record.id]
  end

  def vrp_status_label(vrp)
    return "Rejected" if vrp.status.to_i == 99 || approval_rejected?(vrp)
    return "Final Approved" if vrp.status.to_i == 55 || approval_complete?(vrp)

    if approval_sent?(vrp)
      "Pending at #{approval_approver_name(current_approval_step(vrp))}"
    else
      "Submitted"
    end
  end

  def approval_approver_name(step)
    step&.data&.[]("approver_approved_by").presence || "Approver"
  end

  def vrp_creator_role(vrp)
    return current_app_user&.dig("role") if vrp.created_by_id.blank?

    if model_ready?(:User)
      role = User.find_by(id: vrp.created_by_id)&.role
      return role if role.present?
    end

    return current_app_user&.dig("role") unless model_ready?(:ModuleRecord)

    ModuleRecord.find_by(id: vrp.created_by_id)&.data&.[]("role").presence ||
      current_app_user&.dig("role")
  end

  def vrp_creator_stakeholder(vrp)
    return current_app_user&.dig("stakeholder") if vrp.created_by_id.blank?

    if model_ready?(:User)
      stakeholder = User.find_by(id: vrp.created_by_id)&.stakeholder
      return stakeholder if stakeholder.present?
    end

    return current_app_user&.dig("stakeholder") unless model_ready?(:ModuleRecord)

    ModuleRecord.find_by(id: vrp.created_by_id)&.data&.[]("stakeholder").presence || current_app_user&.dig("stakeholder")
  end

  def vrp_creator_identities(vrp)
    identities = []

    if vrp.created_by_id.present? && model_ready?(:User)
      user = User.find_by(id: vrp.created_by_id)
      identities << user_approval_identity(user) if user
    end

    if model_ready?(:User)
      matched_users = []
      matched_users << User.find_by(email: vrp.email) if vrp.email.present?
      matched_users << User.find_by(mobile_no: vrp.mobile_no) if vrp.mobile_no.present?
      matched_users.compact.uniq.each do |user|
        identities << user_approval_identity(user)
      end
    end

    if vrp.created_by_id.present? && model_ready?(:ModuleRecord)
      record = ModuleRecord.find_by(id: vrp.created_by_id)
      identities << record_approval_identity(record) if record
    end

    if model_ready?(:ModuleRecord)
      matched_records = ModuleRecord.where(module_slug: "new-user").select do |record|
        (vrp.email.present? && record.data["email"].to_s.casecmp(vrp.email.to_s).zero?) ||
          (vrp.mobile_no.present? && record.data["mobile_no"].to_s == vrp.mobile_no.to_s)
      end
      matched_records.each do |record|
        identities << record_approval_identity(record)
      end
    end

    identities << current_approval_identity if current_app_user.present?

    identities
      .select { |identity| identity[:stakeholder].present? && (identity[:role].present? || identity_user_name_values(identity).present?) }
      .uniq
  end

  def current_approval_identity
    user_names = [
      current_app_user&.dig("username"),
      current_app_user&.dig("user_name"),
      current_app_user&.dig("name")
    ]

    {
      role: current_app_user&.dig("role").presence || current_app_user&.dig("role_name"),
      stakeholder: current_app_user&.dig("stakeholder"),
      stakeholder_role: current_app_user&.dig("stakeholder_role"),
      user_management_role: current_app_user&.dig("user_management_role"),
      person_type: current_app_user&.dig("person_type"),
      office: current_app_user&.dig("sub_office_name").presence || current_app_user&.dig("office"),
      office_category: current_app_user&.dig("office_category").presence || current_app_user&.dig("office_name"),
      user_name: user_names.compact_blank.first,
      user_names: user_names
    }
  end

  def user_approval_identity(user)
    user_names = [user.user_name, user.full_name]

    {
      role: user.role.presence || (user.role_name if user.respond_to?(:role_name)),
      stakeholder: user.stakeholder,
      stakeholder_role: user.stakeholder_role,
      user_management_role: user.user_management_role,
      person_type: user.respond_to?(:person_type) ? user.person_type : nil,
      office: user.respond_to?(:sub_office_name) ? user.sub_office_name.presence || user.office : user.office,
      office_category: (user.respond_to?(:office_category) ? user.office_category : nil).presence || (user.respond_to?(:office_name) ? user.office_name : nil),
      user_name: user.user_name,
      user_names: user_names
    }
  end

  def record_approval_identity(record)
    full_name = [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ")

    {
      role: record.data["role"].presence || record.data["role_name"],
      stakeholder: record.data["stakeholder"],
      stakeholder_role: record.data["stakeholder_role"],
      user_management_role: record.data["user_management_role"],
      person_type: record.data["person_type"],
      office: record.data["sub_office_name"].presence || record.data["office"],
      office_category: record.data["office_category"].presence || record.data["office_name"],
      user_name: record.data["user_name"],
      user_names: [record.data["user_name"], full_name, record.data["name"]]
    }
  end

  def apply_current_identity_to_vrp(vrp)
    return unless current_app_user.present?

    {
      stakeholder: current_app_user["stakeholder"],
      stakeholder_role: current_app_user["stakeholder_role"],
      role: current_app_user["role"].presence || current_app_user["role_name"],
      user_management_role: current_app_user["user_management_role"],
      person_type: current_app_user["person_type"]
    }.each do |attribute, value|
      next if value.blank? || !vrp.respond_to?("#{attribute}=")
      next if vrp.public_send(attribute).present?

      vrp.public_send("#{attribute}=", value)
    end
  end

  def approval_history_for(vrp)
    return [] unless model_ready?(:ModuleRecord)

    @approval_history_for_cache ||= {}
    cache_key = vrp.id
    return @approval_history_for_cache[cache_key] if @approval_history_for_cache.key?(cache_key)

    @approval_history_for_cache[cache_key] = ModuleRecord
      .where(module_slug: "vrp-approval-history")
      .order(created_at: :asc)
      .select { |record| record.data["vrp_id"].to_i == vrp.id }
  end

  def approval_sent?(vrp)
    approval_history_for(vrp).any? do |record|
      ["Sent for Approval", "Approved", "Rejected"].include?(record.data["action"].to_s)
    end
  end

  def approval_rejected?(vrp)
    approval_history_for(vrp).any? { |record| record.data["action"].to_s == "Rejected" }
  end

  def approval_complete?(vrp)
    steps = approval_steps_for(vrp)
    return false if steps.blank?

    steps.all? { |step| approval_step_closed?(vrp, step) }
  end

  def approved_approval_sequences(vrp)
    approval_history_for(vrp)
      .select { |record| record.data["action"].to_s == "Approved" }
      .map { |record| approval_sequence_from_level(record.data["approval_level"]) }
      .uniq
  end

  def approval_step_closed?(vrp, step)
    closing_approval_history(vrp, step).present?
  end

  def closing_approval_history(vrp, step)
    step_sequence = approval_sequence(step)
    step_approver = normalize_approver_label(approval_approver_name(step))

    approval_history_for(vrp).find do |record|
      ["Approved", "Rejected"].include?(record.data["action"].to_s) &&
        (
          approval_sequence_from_level(record.data["approval_level"]) == step_sequence ||
            normalize_approver_label(record.data["approver"]) == step_approver
        )
    end
  end

  def update_vrp_status!(vrp, status)
    vrp.update_columns(status: status, updated_at: Time.current)
    vrp.status = status
  end

  def log_approval_history(vrp, step, action, remarks)
    return unless model_ready?(:ModuleRecord)

    ModuleRecord.create!(
      module_slug: "vrp-approval-history",
      data: {
        "vrp_id" => vrp.id,
        "approval_level" => step&.data&.[]("approval_level").presence || "Approval",
        "approver" => approval_approver_name(step),
        "action" => action,
        "remarks" => remarks.to_s,
        "status" => vrp_status_label(vrp),
        "action_by" => current_app_user&.dig("name").presence || current_app_user&.dig("username").to_s
      }
    )
  end

  def set_master_options
    sync_existing_vrp_master_records

    @stakeholder_options = text_module_record_options("stakeholder-master", "stakeholder_name_in_english")
    @stakeholder_role_options = text_module_record_options("stakeholder-role", "stakeholder_role")
    @role_options = text_module_record_options("role-name", "role_name")
    @user_management_role_options = text_module_record_options("user-management-role", "user_management_role")
    @person_type_options = text_module_record_options("person-type", "person_type")
    @role_management_mappings = role_management_mappings
    @vrp_type_options = vrp_type_options
    @project_master_options = project_master_options
    @office_management_mappings = office_management_mappings
    @fcoc_options = fcoc_options
    @to_options = to_options
    @current_user_office_name = current_user_office_name
    @cluster_incharge_user_mappings = cluster_incharge_user_mappings
    @cluster_incharge_options = cluster_incharge_options
    @state_options = module_record_options("state-master", "state_name")
    @district_options = module_record_options("district-master", "district_name")
    @block_options = module_record_options("block-master", "block_name")
    @location_hierarchy_mappings = location_hierarchy_mappings
    @gram_panchayat_options = location_gram_panchayat_options
    @village_options = module_record_options("village-master", "village_name")
  end

  def vrp_type_options
    module_options = module_record_options("add-vrp-type", ["jeevika_jankar_type_name", "vrp_type_name"])
    return module_options if module_options.any?

    if model_ready?(:VrpType)
      options = VrpType.where(is_active: true, is_deleted: false).order(:type_name).pluck(:type_name, :id)
      return options if options.any?
    end

    module_record_options("position-type", "position_type_name")
  end

  def project_master_options
    module_record_options("project-master", "project_name")
  end

  def office_management_mappings
    office_mapping_master_mappings
  end

  def current_user_office_category
    return "" if admin_user?

    current_user_model&.then { |user| user.respond_to?(:office_category) ? user.office_category : nil }.presence ||
      current_user_model&.then { |user| user.respond_to?(:office_name) ? user.office_name : nil }.presence ||
      current_user_model&.then { |user| user.respond_to?(:parent_office) ? user.parent_office : nil }.presence ||
      current_app_user&.dig("office_category").presence ||
      current_app_user&.dig("office_name").presence
  end

  def current_user_office_name
    return "" if admin_user?

    user = current_user_model
    (user.respond_to?(:sub_office_name) ? user.sub_office_name : nil).presence ||
      user&.office.presence ||
      current_app_user&.dig("sub_office_name").presence ||
      current_app_user&.dig("office_name").presence ||
      current_app_user&.dig("office").presence
  end

  def current_user_model
    return @current_user_model if defined?(@current_user_model)
    return @current_user_model = nil unless model_ready?(:User)

    username = current_app_user&.dig("username").to_s
    email = current_app_user&.dig("email").to_s
    @current_user_model =
      User.find_by(id: current_app_user_id) ||
      (username.present? ? User.find_by(user_name: username) : nil) ||
      (email.present? ? User.find_by(email: email) : nil)
  end

  def fcoc_options
    current_category = current_user_office_category
    return [[current_category, current_category]] if current_category.present?

    (
      @office_management_mappings.filter_map { |mapping| mapping[:office_category].presence } +
      text_module_record_options("office-category-add", ["office_name", "category_name"])
    ).compact_blank.uniq.map { |office_category| [office_category, office_category] }
  end

  def to_options
    current_category = current_user_office_category
    selected_category = current_category.presence
    offices = @office_management_mappings
      .select { |mapping| selected_category.blank? || mapping[:office_category].to_s.casecmp(selected_category).zero? }
      .filter_map { |mapping| mapping[:office_name].presence }

    offices.compact_blank.uniq.map { |office_name| [office_name, office_name] }
  end

  def mapped_office_name?(office_name)
    normalized_office_name = office_name.to_s.strip.downcase
    return false if normalized_office_name.blank?

    @office_management_mappings.any? do |mapping|
      mapping[:office_name].to_s.strip.downcase == normalized_office_name
    end
  end

  def registered_user_office_mappings
    user_model_office_mappings + module_record_user_office_mappings
  end

  def user_model_office_mappings
    return [] unless model_ready?(:User)

    User.order(created_at: :desc).filter_map do |user|
      next unless user.status.blank? || user.status.to_s.casecmp("Active").zero?

      office_category = user_office_category(user)
      office_name = user_office_name(user)
      next if office_category.blank? && office_name.blank?

      {
        stakeholder: user.respond_to?(:stakeholder) ? user.stakeholder.to_s.strip : "",
        parent_office: user.respond_to?(:parent_office) ? user.parent_office.to_s.strip : "",
        office_category: office_category,
        office_name: office_name,
        office: office_name,
        office_level: ""
      }
    end.uniq
  end

  def module_record_user_office_mappings
    return [] unless model_ready?(:ModuleRecord)

    ModuleRecord
      .where(module_slug: "new-user")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .filter_map do |record|
        office_category = record.data["office_category"].presence || record.data["office_name"].presence || record.data["parent_office"].to_s.strip
        office_name = record.data["sub_office_name"].presence || record.data["office"].to_s.strip
        next if office_category.blank? && office_name.blank?

        {
          stakeholder: record.data["stakeholder"].to_s.strip,
          parent_office: record.data["parent_office"].to_s.strip,
          office_category: office_category,
          office_name: office_name,
          office: office_name,
          office_level: ""
        }
      end.uniq
  end

  def office_category_master_mappings
    return [] unless model_ready?(:ModuleRecord)

    ModuleRecord
      .where(module_slug: ["office-category-add", "office-mapping-add"])
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .map do |record|
        office_category = first_present_data(record, "office_category", "category_name", "office_name", "office").to_s.strip
        office_name = record.module_slug == "office-mapping-add" ? first_present_data(record, "sub_office_name", "office_mapping", "office").to_s.strip : ""
        {
          stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
          parent_office: first_present_data(record, "parent_office", "parent_office_name", "parent_category").to_s.strip,
          office_category: office_category,
          office_name: office_name,
          office: office_name,
          office_level: first_present_data(record, "office_level").to_s.strip
        }
      end
      .reject { |mapping| mapping[:office_category].blank? }
      .uniq
  end

  def office_mapping_master_mappings
    office_category_master_mappings.select { |mapping| mapping[:office_name].present? }
  end

  def user_office_category(user)
    (user.respond_to?(:office_category) ? user.office_category : nil).presence ||
      (user.respond_to?(:office_name) ? user.office_name : nil).presence ||
      (user.respond_to?(:parent_office) ? user.parent_office : nil).to_s.strip
  end

  def user_office_name(user)
    (user.respond_to?(:sub_office_name) ? user.sub_office_name : nil).presence ||
      (user.respond_to?(:office) ? user.office : nil).to_s.strip
  end

  def cluster_incharge_options
    cluster_incharge_user_mappings.map { |mapping| [mapping[:label], mapping[:value]] }
  end

  def cluster_incharge_user_mappings
    hierarchy_cluster_incharge_labels
      .filter_map { |label| cluster_mapping_from_hierarchy_label(label) }
      .map { |mapping| enrich_cluster_mapping_from_user(mapping) }
      .uniq { |mapping| normalize_approver_label(mapping[:value]) }
  end

  def cluster_mapping_from_hierarchy_label(label)
    label = label.to_s.strip
    return if label.blank?

    name = label.sub(/\s*\([^)]*\)\s*\z/, "").strip
    return if name.blank?

    {
      label: label,
      value: name,
      office_category: "",
      office_name: "",
      parent_office: ""
    }
  end

  def enrich_cluster_mapping_from_user(mapping)
    return mapping unless model_ready?(:User)

    user = User
      .order(:first_name, :last_name, :user_name)
      .detect do |candidate|
        candidate_status = candidate.respond_to?(:status) ? candidate.status : nil
        next false unless candidate_status.blank? || candidate_status.to_s.casecmp("Active").zero?

        candidate_name = (candidate.respond_to?(:full_name) ? candidate.full_name : nil).presence ||
          (candidate.respond_to?(:user_name) ? candidate.user_name : nil)
        normalize_approver_label(candidate_name) == normalize_approver_label(mapping[:value]) ||
          normalize_approver_label(candidate.respond_to?(:user_name) ? candidate.user_name : nil) == normalize_approver_label(mapping[:value])
      end
    return mapping unless user

    role = (user.respond_to?(:role_name) ? user.role_name : nil).presence ||
      (user.respond_to?(:role) ? user.role : nil)
    name = (user.respond_to?(:full_name) ? user.full_name : nil).presence ||
      (user.respond_to?(:user_name) ? user.user_name : nil) ||
      mapping[:value]
    mapping.merge(
      label: role.present? ? "#{name}(#{role})" : mapping[:label],
      value: name,
      office_category: user_office_category(user),
      office_name: user_office_name(user),
      parent_office: user.respond_to?(:parent_office) ? user.parent_office.to_s.strip : ""
    )
  end

  def hierarchy_cluster_incharge_labels
    return [] unless model_ready?(:ModuleRecord)

    labels = ModuleRecord
      .where(module_slug: "user-hierarchy-mapping")
      .order(updated_at: :desc)
      .select { |record| active_module_record?(record) }
      .select { |record| admin_user? || hierarchy_level_1_matches_current_user?(record.data["level_1_user"]) }
      .flat_map { |record| hierarchy_cluster_incharge_labels_for_record(record) }
      .compact_blank
      .uniq

    (labels + dashboard_visible_hierarchy_cluster_labels).compact_blank.uniq
  end

  def dashboard_visible_hierarchy_cluster_labels
    return [] unless model_ready?(:ModuleRecord)

    current_labels = current_hierarchy_user_labels
    return [] if current_labels.blank?

    ModuleRecord
      .where(module_slug: "user-hierarchy-mapping")
      .order(updated_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        next [] unless hierarchy_level_1_matches_current_user?(record.data["level_1_user"])

        hierarchy_level_2_labels_for_record(record).select { |label| cluster_incharge_user_label?(label) || user_record_cluster_incharge_label?(label) }
      end
      .compact_blank
      .uniq
  end

  def hierarchy_level_1_matches_current_user?(level_1_user)
    stored_labels = hierarchy_label_match_values(level_1_user)
    return false if stored_labels.blank?

    current_hierarchy_user_labels.any? do |label|
      (stored_labels & hierarchy_label_match_values(label)).any?
    end
  end

  def current_hierarchy_user_labels
    role = current_app_user&.dig("role").presence || current_app_user&.dig("role_name")
    name = current_app_user&.dig("name").to_s.strip
    username = current_app_user&.dig("username").to_s.strip
    labels = [
      name,
      username,
      role.present? && name.present? ? "#{name} (#{role})" : nil,
      role.present? && username.present? ? "#{username} (#{role})" : nil
    ]

    user = current_user_model
    if user
      user_role = (user.respond_to?(:role) ? user.role : nil).presence || (user.respond_to?(:role_name) ? user.role_name : nil)
      full_name = user.respond_to?(:full_name) ? user.full_name.to_s.strip : ""
      user_name = user.respond_to?(:user_name) ? user.user_name.to_s.strip : ""
      labels.concat([
        full_name,
        user_name,
        user_role.present? && full_name.present? ? "#{full_name} (#{user_role})" : nil,
        user_role.present? && user_name.present? ? "#{user_name} (#{user_role})" : nil
      ])
    end

    labels.compact_blank.uniq
  end

  def hierarchy_label_match_values(label)
    value = label.to_s.strip
    base = value.sub(/\s*\([^)]*\)\s*\z/, "").strip
    [value, base].flat_map do |item|
      [
        normalize_approver_label(item),
        normalize_hierarchy_label(item)
      ]
    end.reject { |item| item.blank? || item.length < 3 }.uniq
  end

  def hierarchy_cluster_incharge_labels_for_record(record)
    hierarchy_level_2_labels_for_record(record).select { |label| cluster_incharge_user_label?(label) || user_record_cluster_incharge_label?(label) }
  end

  def hierarchy_level_2_labels_for_record(record)
    mappings = record.data["level_2_mappings"]
    mappings = mappings.values if mappings.is_a?(Hash)

    labels = Array(mappings).flat_map do |mapping|
      next [] unless mapping.respond_to?(:[])

      collapsed_hierarchy_user_labels(mapping["level_2_user"], mapping["level_3_users"])
    end

    labels = collapsed_hierarchy_user_labels(record.data["level_2_users"].presence || record.data["level_2_user"], record.data["level_3_users"].presence || record.data["level_3_user"]) if labels.blank?
    labels
  end

  def collapsed_hierarchy_user_labels(*values)
    values.flatten.flat_map do |value|
      value.to_s.split(";").flat_map do |segment|
        user_segment = segment.include?("->") ? segment.split("->", 2).last : segment
        user_segment.to_s.split(",")
      end
    end.map(&:strip).compact_blank.uniq
  end

  def cluster_incharge_user_label?(label)
    role_text = label.to_s[/\(([^)]*)\)\s*\z/, 1].to_s
    role_text.downcase.include?("cluster") || label.to_s.downcase.include?("cluster incharge")
  end

  def user_record_cluster_incharge_label?(label)
    return false unless model_ready?(:User)

    normalized_label = normalize_approver_label(label)
    User.order(:first_name, :last_name, :user_name).any? do |user|
      name = (user.respond_to?(:full_name) ? user.full_name : nil).presence ||
        (user.respond_to?(:user_name) ? user.user_name : nil)
      next false unless normalize_approver_label(name) == normalized_label ||
        normalize_approver_label(user.respond_to?(:user_name) ? user.user_name : nil) == normalized_label

      role = (user.respond_to?(:role_name) ? user.role_name : nil).presence ||
        (user.respond_to?(:role) ? user.role : nil)
      role.to_s.downcase.include?("cluster")
    end
  end

  def normalize_hierarchy_label(label)
    label.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def ics_options
    module_record_options("ics-master", "ics_name")
  end

  def module_record_options(module_slug, field_key)
    return [] unless model_ready?(:ModuleRecord)

    field_keys = Array(field_key)
    ModuleRecord
      .where(module_slug: module_slug)
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .filter_map do |record|
        label = module_slug == "gram-panchayat-master" ? gram_panchayat_name_from_record(record) : first_present_data(record, *field_keys)
        [label, record.id] if label
      end
      .uniq { |label, _value| label }
      .sort_by { |label, _value| label.to_s.downcase }
  end

  def text_module_record_options(module_slug, field_key)
    return [] unless model_ready?(:ModuleRecord)

    field_keys = Array(field_key)
    ModuleRecord
      .where(module_slug: module_slug)
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map { |record| field_keys.filter_map { |key| record.data[key].presence } }
      .uniq
  end

  def role_management_mappings
    return [] unless model_ready?(:ModuleRecord)

    stakeholder_role_mappings = ModuleRecord
      .where(module_slug: "stakeholder-role")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        stakeholder_role = first_present_data(record, "stakeholder_role").to_s.strip
        [stakeholder_role].compact_blank.map do |stakeholder_role_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: stakeholder_role,
            stakeholder_role_label: stakeholder_role_label,
            role: "",
            role_label: "",
            role_name: "",
            role_name_label: "",
            user_management_role: "",
            user_management_role_label: "",
            person_type: "",
            person_type_label: ""
          }
        end
      end

    role_mappings = ModuleRecord
      .where(module_slug: "role-management")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        role = first_present_data(record, "role", "role_name").to_s.strip
        mapping_labels_for_option(role, :role).map do |role_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: first_present_data(record, "stakeholder_role").to_s.strip,
            role: role,
            role_label: role_label,
            role_name: "",
            role_name_label: "",
            user_management_role: "",
            user_management_role_label: "",
            person_type: ""
          }
        end
      end

    user_management_role_mappings = ModuleRecord
      .where(module_slug: "user-management-role")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        user_management_role = first_present_data(record, "user_management_role").to_s.strip
        mapping_labels_for_option(user_management_role, :user_management_role).map do |user_management_role_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: first_present_data(record, "stakeholder_role").to_s.strip,
            role: first_present_data(record, "role", "role_name").to_s.strip,
            role_name: "",
            role_name_label: "",
            user_management_role: user_management_role,
            user_management_role_label: user_management_role_label,
            person_type: ""
          }
        end
      end

    person_type_mappings = ModuleRecord
      .where(module_slug: "person-type")
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .flat_map do |record|
        person_type = first_present_data(record, "person_type").to_s.strip
        mapping_labels_for_option(person_type, :person_type).map do |person_type_label|
          {
            stakeholder: first_present_data(record, "stakeholder_category", "stakeholder_name", "stakeholder").to_s.strip,
            stakeholder_role: first_present_data(record, "stakeholder_role").to_s.strip,
            role: first_present_data(record, "role", "role_name").to_s.strip,
            role_name: "",
            role_name_label: "",
            user_management_role: first_present_data(record, "user_management_role").to_s.strip,
            person_type: person_type,
            person_type_label: person_type_label
          }
        end
      end

    (stakeholder_role_mappings + role_mappings + user_management_role_mappings + person_type_mappings)
      .reject { |mapping| mapping[:stakeholder_role].blank? && mapping[:role].blank? && mapping[:role_name].blank? && mapping[:user_management_role].blank? && mapping[:person_type].blank? }
      .uniq
  end

  def label_with_registered_name(value, attribute)
    mapping_labels_for_option(value, attribute).first.to_s
  end

  def mapping_labels_for_option(value, attribute)
    return [] if value.blank?

    [value]
  end

  def registered_names_for_option(attribute, value)
    return [] if value.blank?

    (
      registered_vrp_names_for_option(attribute, value) +
      registered_user_names_for_option(attribute, value) +
      registered_module_user_names_for_option(attribute, value)
    ).compact_blank.uniq
  end

  def registered_vrp_names_for_option(attribute, value)
    return [] unless model_ready?(:Vrp)
    return [] unless Vrp.column_names.include?(attribute.to_s)

    Vrp.where(attribute => value).order(updated_at: :desc).filter_map { |vrp| vrp.name.presence }
  end

  def registered_user_names_for_option(attribute, value)
    return [] unless model_ready?(:User)
    return [] unless User.column_names.include?(attribute.to_s)

    User.where(attribute => value).order(updated_at: :desc).filter_map { |user| user.full_name.presence || user.user_name.presence }
  end

  def registered_module_user_names_for_option(attribute, value)
    return [] unless model_ready?(:ModuleRecord)

    key = attribute.to_s
    ModuleRecord
      .where(module_slug: "new-user")
      .order(updated_at: :desc)
      .select { |record| active_module_record?(record) && record.data[key].to_s.strip.casecmp(value.to_s.strip).zero? }
      .filter_map { |record| [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence || record.data["user_name"].presence }
  end

  def location_hierarchy_mappings
    return [] unless model_ready?(:ModuleRecord)

    states = active_records_for_location("state-master").map do |record|
      location_row(record, state: first_present_data(record, "state_name"))
    end

    districts = active_records_for_location("district-master").map do |record|
      location_row(record,
        state: location_name_from_record(record, "state_name", "state", "state_id", "state_code"),
        district: first_present_data(record, "district_name"))
    end

    blocks = active_records_for_location("block-master").map do |record|
      location_row(record,
        state: location_name_from_record(record, "state_name", "state", "state_id", "state_code"),
        district: location_name_from_record(record, "district_name", "district", "district_id", "district_code"),
        block: first_present_data(record, "block_name"))
    end

    gram_panchayats = active_records_for_location("gram-panchayat-master").map do |record|
      location_row(record,
        state: location_name_from_record(record, "state_name", "state", "state_id", "state_code"),
        district: location_name_from_record(record, "district_name", "district", "district_id", "district_code"),
        block: location_name_from_record(record, "block_name", "block", "block_id", "block_code"),
        gram_panchayat: gram_panchayat_name_from_record(record))
    end

    villages = active_records_for_location("village-master").map do |record|
      location_row(record,
        state: location_name_from_record(record, "state_name", "state", "state_id", "state_code"),
        district: location_name_from_record(record, "district_name", "district", "district_id", "district_code"),
        block: location_name_from_record(record, "block_name", "block", "block_id", "block_code"),
        gram_panchayat: gram_panchayat_name_from_record(record),
        village: first_present_data(record, "village_name", "village", "name"))
    end

    lg_directory_rows = active_records_for_location("lg-directory-list").map do |record|
      location_row(record,
        state: first_present_data(record, "state", "state_name"),
        district: first_present_data(record, "district", "district_name"),
        block: first_present_data(record, "block", "cd_block_name"),
        gram_panchayat: gram_panchayat_name_from_record(record),
        village: first_present_data(record, "village", "village_name"))
    end

    states + districts + blocks + gram_panchayats + villages + lg_directory_rows
  end

  def active_records_for_location(module_slug)
    ModuleRecord
      .where(module_slug: module_slug)
      .order(created_at: :desc)
      .select { |record| active_module_record?(record) }
  end

  def location_row(record, values)
    row = { id: record.id.to_s }
    values.each { |key, value| row[key] = value.to_s.strip if value.present? }
    row
  end

  def location_gram_panchayat_options
    return [] unless model_ready?(:ModuleRecord)

    active_records_for_location(["gram-panchayat-master", "lg-directory-list", "village-master"])
      .filter_map do |record|
        label = gram_panchayat_name_from_record(record)
        next if label.blank? || code_like_location_value?(label)

        [label, record.id]
      end
      .uniq { |label, _value| label.to_s.downcase }
      .sort_by { |label, _value| label.to_s.downcase }
  end

  def gram_panchayat_name_from_record(record)
    direct_name = first_non_code_data(record, "gram_panchayat_name", "gram_panchayat", "gp_name", "gram_name", "name")
    return direct_name if direct_name.present? && !code_like_location_value?(direct_name)

    code = first_present_data(record, "gp_code", "gram_code", "gram_panchayat_code", "gram_panchayat_id", "gram_panchayat", "gram_panchayat_name", "gp_name", "gram_name")
    return direct_name.presence || code if code.blank?

    gram_panchayat_name_lookup[code.to_s.strip.downcase].presence ||
      (direct_name.present? && !code_like_location_value?(direct_name) ? direct_name : nil) ||
      code
  end

  def gram_panchayat_name_lookup
    @gram_panchayat_name_lookup ||= active_records_for_location(["gram-panchayat-master", "lg-directory-list", "village-master"])
      .each_with_object({}) do |record, lookup|
        label = first_non_code_data(record, "gram_panchayat_name", "gram_panchayat", "gp_name", "gram_name", "name")
        next if label.blank? || code_like_location_value?(label)

        %w[gp_code gram_code gram_panchayat_code gram_panchayat_id gram_panchayat gram_panchayat_name gp_name gram_name name].each do |key|
          value = record.data[key].to_s.strip
          lookup[value.downcase] = label if value.present? && code_like_location_value?(value)
        end
      end
  end

  def location_name_from_record(record, *keys)
    first_non_code_data(record, *keys)
  end

  def first_non_code_data(record, *keys)
    values = keys.filter_map { |key| record.data[key].to_s.strip.presence }
    values.find { |value| !code_like_location_value?(value) } || values.first
  end

  def code_like_location_value?(value)
    value.to_s.strip.match?(/\A[\d\s.\/-]+\z/)
  end

  def first_present_data(record, *keys)
    keys.filter_map { |key| record.data[key].presence }.first
  end

  def active_module_record?(record)
    return false if truthy_module_flag?(record.data["deleted"]) ||
      truthy_module_flag?(record.data["is_deleted"]) ||
      truthy_module_flag?(record.data["discarded"])

    status = record.data["status"].to_s.strip
    return true if status.blank?

    status.casecmp("Active").zero?
  end

  def truthy_module_flag?(value)
    ["1", "true", "yes", "deleted"].include?(value.to_s.strip.downcase)
  end

  def blank_display(value)
    value.presence || ""
  end

  def module_record_label(module_slug, id, field_key)
    return "" if id.blank? || !model_ready?(:ModuleRecord)

    record = ModuleRecord.find_by(module_slug: module_slug, id: id)
    label = module_record_display_label(module_slug, record, field_key)
    return label if label.present?

    id.to_s.match?(/\A\d+\z/) ? "" : id.to_s
  end

  def module_record_labels(module_slug, ids, field_key)
    Array(ids)
      .filter_map { |id| module_record_label(module_slug, id, field_key).presence }
      .join(", ")
  end

  def vrp_type_labels(ids)
    ids = Array(ids).reject(&:blank?)
    return "" if ids.blank?

    if model_ready?(:VrpType)
      labels = VrpType.where(id: ids).pluck(:type_name)
      return labels.join(", ") if labels.any?
    end

    module_record_labels("add-vrp-type", ids, ["jeevika_jankar_type_name", "vrp_type_name"])
  end

  def module_record_display_label(module_slug, record, field_key)
    return "" unless record

    case module_slug
    when "gram-panchayat-master"
      gram_panchayat_name_from_record(record)
    when "village-master"
      first_present_data(record, "village_name", "village", "name")
    else
      Array(field_key).filter_map { |key| record.data[key].presence }.first
    end.to_s
  end

  def sync_existing_vrp_master_records
    return unless model_ready?(:ModuleRecord)

    ModuleRecord.where(module_slug: ["bank-master", "position-type", "add-vrp-type"]).find_each do |record|
      case record.module_slug
      when "bank-master"
        sync_bank_master(record)
      when "position-type", "add-vrp-type"
        sync_vrp_type(record)
      end
    end
  end

  def sync_bank_master(record)
    return unless model_ready?(:VrpBankMaster)

    name = record.data["bank_name"].to_s.strip
    return if name.blank?

    bank = VrpBankMaster.find_or_initialize_by(name: name)
    bank.is_active = record.data["status"].to_s != "Inactive" if bank.respond_to?(:is_active=)
    bank.is_deleted = false if bank.respond_to?(:is_deleted=)
    bank.save(validate: false)
  end

  def sync_vrp_type(record)
    return unless model_ready?(:VrpType)

    type_name = (record.data["position_type_name"].presence || record.data["jeevika_jankar_type_name"].presence || record.data["vrp_type_name"]).to_s.strip
    return if type_name.blank?

    vrp_type = VrpType.find_or_initialize_by(type_name: type_name)
    vrp_type.is_active = record.data["status"].to_s != "Inactive" if vrp_type.respond_to?(:is_active=)
    vrp_type.is_deleted = false if vrp_type.respond_to?(:is_deleted=)
    vrp_type.save(validate: false)
  end

  def model_ready?(name)
    klass = name.to_s.safe_constantize
    klass.present? && (!klass.respond_to?(:table_exists?) || klass.table_exists?)
  end

  def form_options_payload
    sync_existing_vrp_master_records

    office_mappings = office_management_mappings
    @office_management_mappings = office_mappings

    {
      vrp_types: options_as_hashes(vrp_type_options),
      projects: options_as_hashes(project_master_options),
      genders: [{ label: "Male", value: "male" }, { label: "Female", value: "female" }],
      states: options_as_hashes(module_record_options("state-master", "state_name")),
      districts: options_as_hashes(module_record_options("district-master", "district_name")),
      blocks: options_as_hashes(module_record_options("block-master", "block_name")),
      gram_panchayats: options_as_hashes(location_gram_panchayat_options),
      villages: options_as_hashes(module_record_options("village-master", "village_name")),
      banks: bank_options_payload,
      fcoc_options: options_as_hashes(fcoc_options_for_api(office_mappings)),
      to_options: options_as_hashes(to_options_for_api(office_mappings)),
      cluster_incharge_options: options_as_hashes(cluster_incharge_options),
      location_hierarchy: location_hierarchy_mappings
    }
  end

  def options_as_hashes(options)
    Array(options).map do |label, value|
      { label: label.to_s, value: value }
    end
  end

  def bank_options_payload
    return [] unless model_ready?(:VrpBankMaster)

    VrpBankMaster.where(is_deleted: false).order(:name).map do |bank|
      { label: bank.name, value: bank.id }
    end
  rescue StandardError
    []
  end

  def fcoc_options_for_api(office_mappings)
    current_category = current_user_office_category
    return [[current_category, current_category]] if current_category.present?

    (
      office_mappings.filter_map { |mapping| mapping[:office_category].presence } +
      text_module_record_options("office-category-add", ["office_name", "category_name"])
    ).compact_blank.uniq.map { |office_category| [office_category, office_category] }
  end

  def to_options_for_api(office_mappings)
    current_category = current_user_office_category
    selected_category = current_category.presence
    offices = office_mappings
      .select { |mapping| selected_category.blank? || mapping[:office_category].to_s.casecmp(selected_category).zero? }
      .filter_map { |mapping| mapping[:office_name].presence }

    offices.compact_blank.uniq.map { |office_name| [office_name, office_name] }
  end

  def list_row_payload(vrp)
    {
      id: vrp.id,
      user_name: vrp.user_name,
      status: vrp.status,
      name: vrp.name,
      father_husband_name: vrp.father_husband_name,
      gender: vrp.gender,
      date_of_birth: vrp.date_of_birth&.strftime("%d-%m-%Y"),
      date_of_joining: vrp.date_of_joining&.strftime("%d-%m-%Y"),
      aadhar_no: vrp.aadhar_no.to_s.gsub(/\d(?=\d{4})/, "x"),
      account_no: vrp.account_no,
      ifsc_code: vrp.ifsc_code,
      bank_name: vrp.bank_name.presence || vrp.vrp_bank_master&.name,
      address: vrp.address,
      mobile_no: vrp.mobile_no,
      email: vrp.email,
      emergency_no: vrp.emergency_no,
      fcoc: vrp.fcoc,
      to_name: vrp.to_name,
      cluster_incharge: vrp.cluster_incharge,
      experience_in_years: vrp.experience_in_years,
      is_active: vrp.is_active,
      registered_by: registered_by_name(vrp),
      mapped_cluster_name: vrp.cluster_incharge.presence || "-",
      status_label: vrp_status_label(vrp),
      vrp_type_ids: Array(vrp.vrp_type_ids),
      vrp_type_labels: vrp_type_labels(vrp.vrp_type_ids),
      project_master_ids: Array(vrp.project_master_ids),
      gram_panchayat_ids: Array(vrp.gram_panchayat_ids),
      village_ids: Array(vrp.village_ids)
    }
  end

  def detail_payload(vrp)
    profile = vrp.vrp_profile
    list_row_payload(vrp).merge(
      aadhar_no_full: vrp.aadhar_no,
      branch: vrp.branch,
      vrp_bank_master_id: vrp.vrp_bank_master_id,
      stakeholder: vrp.stakeholder,
      stakeholder_role: vrp.stakeholder_role,
      role: vrp.role,
      user_management_role: vrp.user_management_role,
      person_type: vrp.person_type,
      can_approve: current_user_can_approve?(vrp),
      can_send_for_approval: own_vrps.exists?(id: vrp.id) && !approval_sent?(vrp) && ![31, 32, 55].include?(vrp.status.to_i),
      approval_steps: approval_steps_for(vrp).map { |step| approval_step_payload(step, vrp) },
      approval_history: approval_history_for(vrp).map { |record| approval_history_payload(record) },
      current_approval_step: (step = current_approval_step(vrp)) && approval_step_payload(step, vrp),
      profile: profile && {
        id: profile.id,
        state_id: profile.state_id,
        district_id: profile.district_id,
        block_id: profile.block_id,
        gram_panchayat_id: profile.gram_panchayat_id,
        village_id: profile.village_id
      },
      photo_url: attachment_url(vrp.photo),
      aadhar_upload_url: attachment_url(vrp.aadhar_upload),
      bank_passbook_upload_url: attachment_url(vrp.bank_passbook_upload)
    )
  end

  def approval_queue_row_payload(vrp)
    step = approval_display_step(vrp)
    {
      id: vrp.id,
      name: vrp.name,
      user_name: vrp.user_name,
      mobile_no: vrp.mobile_no,
      status: vrp.status,
      status_label: vrp_status_label(vrp),
      approval_level: step&.data&.[]("approval_level").presence || "Approval",
      approver: step&.data&.[]("approver_approved_by").presence || "-",
      can_act: current_user_can_approve?(vrp),
      registered_by: registered_by_name(vrp),
      date_of_joining: vrp.date_of_joining&.strftime("%d-%m-%Y")
    }
  end

  def approval_step_payload(step, vrp)
    {
      id: step.id,
      approval_level: step.data["approval_level"],
      approver: approval_approver_name(step),
      sequence: approval_sequence(step),
      closed: approval_step_closed?(vrp, step)
    }
  end

  def approval_history_payload(record)
    {
      id: record.id,
      approval_level: record.data["approval_level"],
      approver: record.data["approver"],
      action: record.data["action"],
      remarks: record.data["remarks"],
      status: record.data["status"],
      action_by: record.data["action_by"],
      created_at: record.created_at
    }
  end

  def attachment_url(attachment)
    return nil unless attachment&.attached?

    Rails.application.routes.url_helpers.rails_blob_url(attachment, only_path: true)
  rescue StandardError
    nil
  end
end
