# frozen_string_literal: true

# Farmer Target module APIs for React Native.
# Stores ModuleRecord rows with the same slugs as the web UI (ModulesController untouched).
class FarmerTargetApi
  MAX_TRAINING_PHOTO_SIZE = 5.megabytes
  TRAINING_PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  TRAINING_PHOTO_UPLOAD_KEYS = %w[
    training_photo_upload_with_geo_tag
    photo_front_view
    photo_back_view
    photo_close_up_view
    photo_long_shot
  ].freeze
  OTHER_TARGET_SLUGS = %w[seed-distribution-target papl360-target other-target other-target-with-farmer].freeze
  TARGET_SLUGS = (%w[training-form add-farmer-form] + OTHER_TARGET_SLUGS).freeze

  def initialize(current_app_user:, module_slug:, exclude_record_id: nil)
    @current_app_user = current_app_user || {}
    @module_slug = module_slug.to_s
    @exclude_record_id = exclude_record_id
  end

  def list
    records = ModuleRecord
      .where(module_slug: @module_slug)
      .order(created_at: :desc)
      .to_a
    records = records.select { |record| visible?(record) } if vrp_login_user?
    # Web intentionally shows the newest 100 raw rows, then collapses rows
    # belonging to the same session. On current production data that is 99
    # visible sessions; grouping all historic rows instead produced 401.
    records = grouped_training_list_records(records.first(100)) if @module_slug == "training-form"
    records.map { |record| record_payload(record) }
  end

  def find(id)
    record = ModuleRecord.find_by(id: id, module_slug: @module_slug)
    return nil unless record && visible?(record)

    record
  end

  def create(raw_attrs)
    upload_errors = training_photo_upload_errors(raw_attrs) + other_target_upload_errors(raw_attrs)
    return { success: false, errors: upload_errors } if upload_errors.any?

    data = normalize_incoming(raw_attrs)
    data = normalize_for_slug(data)
    errors = validation_errors(data)
    return { success: false, errors: errors } if errors.any?

    record = ModuleRecord.new(module_slug: @module_slug, data: data)
    if record.save
      { success: true, record: record }
    else
      { success: false, errors: record.errors.full_messages }
    end
  end

  def update(record, raw_attrs)
    upload_errors = training_photo_upload_errors(raw_attrs) + other_target_upload_errors(raw_attrs)
    return { success: false, errors: upload_errors } if upload_errors.any?

    # An edit carries only the fields that changed, so the saved row is the
    # starting point: anything left out — uploads above all — stays as it is.
    incoming = normalize_incoming(raw_attrs)
    @farmer_selection_submitted = incoming.key?("selected_farmer_ids")
    data = record.data.merge(incoming)
    @retained_farmer_ids = Array(record.data["selected_farmer_ids"]).map(&:to_s).compact_blank.uniq
    # The mapping the edit names, or the one the record was already saved
    # against. Either way it is only accepted once the edit is checked against
    # it, so naming an id is not a way to reach a different target.
    @retained_target_mapping_id = data["target_mapping_id"].presence ||
      record.data["target_mapping_id"].presence
    data = normalize_for_slug(data)
    # An edit changes the record, never whose record it is.  Without this a
    # caller could post created_by_id and walk off with someone else's form.
    record.data.each { |key, value| data[key] = value if key.start_with?("created_by") }
    errors = validation_errors(data)
    return { success: false, errors: errors } if errors.any?

    if training_edit_needs_approval?
      revision = TrainingEditApproval.submit!(record: record, proposed: data, actor: current_app_user)
      return { success: true, record: record, revision: revision, pending_approval: true }
    end

    if record.update(data: data)
      { success: true, record: record, ignored_fields: ignored_fields(incoming, data) }
    else
      { success: false, errors: record.errors.full_messages }
    end
  rescue TrainingEditApproval::InvalidTransition => error
    { success: false, errors: [error.message] }
  end

  # The contact number, the Jeevika Jankar and the activity names belong to the
  # target the record is mapped to and are rewritten from there on every save,
  # which is why the web form shows them read only.  Answering "updated
  # successfully" while quietly dropping such a value made the edit look like it
  # had worked, so the caller is told which fields did not take.
  def ignored_fields(incoming, data)
    Hash(incoming).keys.reject do |key|
      sent = incoming[key]
      # Uploads and id lists are reshaped on the way in, so a difference there
      # is expected rather than a dropped edit.
      sent.is_a?(Array) || sent.is_a?(Hash) || sent.to_s.strip == data[key].to_s.strip
    end
  end

  # The month dropdown on its own. Going through form_options built the whole
  # form - target mappings, farmers, staff lists - to read one field off it.
  def month_options
    case @module_slug
    when "training-form"
      training_target_month_options
    when *OTHER_TARGET_SLUGS
      seed_distribution_target_month_options
    else
      []
    end
  end

  def form_options
    case @module_slug
    when "training-form"
      {
        form_fields: training_form_fields,
        autofill: target_form_autofill,
        current_vrp: current_seed_target_vrp_option,
        months: training_target_month_options,
        target_mappings: training_target_mappings,
        people_options: training_people_options,
        training_methods: ["Input Demo INM", "Input Demo PM", "FFS", "OPG Training"]
      }
    when *OTHER_TARGET_SLUGS
      {
        form_fields: other_target_form_fields,
        autofill: target_form_autofill,
        months: seed_distribution_target_month_options,
        target_mappings: seed_distribution_target_mappings,
        current_vrp: current_seed_target_vrp_option,
        upload_constraints: other_target_upload_constraints
      }
    when "add-farmer-form"
      {
        mappings: add_farmer_form_mappings
      }
    else
      {}
    end
  end

  # Other Target with Farmer offers everyone currently registered in the
  # target's villages, not only the farmers picked when the target was mapped.
  # The mapped number stays the target; the Jeevika Jankar still chooses who
  # they actually worked with, including farmers registered since. The form
  # itself carries no farmers - they are loaded once a target is chosen, which
  # is why this is a separate call rather than part of the mapping list.
  def live_target_farmers(target_mapping_id)
    empty = { farmers: [], completed_farmer_ids: [], target_farmer_ids: [] }
    return empty unless model_ready?(:TargetMapping)

    target = training_target_scope.find_by(id: target_mapping_id)
    return empty unless target

    mapped_ids = target_farmer_ids(target)
    village_ids = target_village_ids(target)
    live_ids = (mapped_ids + local_village_farmer_ids(village_ids) +
      external_village_farmer_details(village_ids).keys).map(&:to_s).compact_blank.uniq

    {
      farmers: resolve_live_farmer_details(live_ids, mapped_ids, village_ids),
      completed_farmer_ids: other_target_completed_farmer_ids_for(target.id),
      target_farmer_ids: mapped_ids
    }
  end

  # The training form offers every farmer the target's villages hold today, not
  # only the ones picked when the target was mapped - the mapped quantity is the
  # target, it does not cap who the Jeevika Jankar may say they trained. The
  # farmers are loaded once the activity is narrowed down, so only the villages
  # actually in play are looked up.
  def live_training_farmers(filters = {})
    @training_mapping_filters = filters.to_h.stringify_keys
    return { farmers: [], completed_farmer_ids: [], target_mapping_ids: [] } unless model_ready?(:TargetMapping)

    targets = filtered_training_target_scope.includes(:vrp).to_a
    village_ids = targets.flat_map { |target| target_village_ids(target) }.uniq
    mapped_ids = targets.flat_map { |target| target_farmer_ids(target) }.map(&:to_s).uniq
    live_ids = (mapped_ids + local_village_farmer_ids(village_ids) +
      external_village_farmer_details(village_ids).keys).map(&:to_s).compact_blank.uniq
    completed = targets.flat_map { |target| completed_training_farmer_ids_for(target, live_ids) }
      .map(&:to_s).uniq

    { farmers: resolve_live_farmer_details(live_ids, mapped_ids, village_ids),
      completed_farmer_ids: completed,
      target_mapping_ids: targets.map { |target| target.id.to_s } }
  end

  # Lightweight read path: filters run before farmer hydration and no form/people
  # options are built for the mapped-farmers endpoint.
  def training_mappings(filters = {})
    @training_mapping_filters = filters.to_h.stringify_keys
    training_target_mappings
  end

  def record_payload(record)
    payload = {
      id: record.id,
      module_slug: record.module_slug,
      created_at: record.created_at,
      updated_at: record.updated_at,
      data: record.module_slug == "training-form" ? TrainingParticipantCounts.data(record.data) : record.data
    }
    if record.module_slug == "training-form"
      payload[:photo_count] = TRAINING_PHOTO_UPLOAD_KEYS.flat_map { |key| Array(record.data[key]) }.compact_blank.uniq.size
    end
    payload
  end

  private

  attr_reader :current_app_user

  # The web Training Form List renders one row per training session even when
  # legacy/imported data stores that session in several ModuleRecord rows. Keep
  # the app list on the identical session key instead of returning raw rows.
  def grouped_training_list_records(records)
    records.group_by do |record|
      data = record.data
      farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq.sort
      [
        data["month"],
        data["ics_block"].presence || data["ics"],
        data["gram_name"].presence || data["village"],
        data["trainer_name"],
        data["training_date"],
        data["training_location"],
        farmer_ids
      ].map { |item| item.is_a?(Array) ? item : item.to_s.strip.downcase }
    end.values.map(&:first)
  end

  def normalize_incoming(raw_attrs)
    data = {}
    Hash(raw_attrs).each do |key, value|
      key = key.to_s
      next if %w[controller action format token authenticity_token].include?(key)

      data[key] = normalize_incoming_value(value)
    end
    data
  end

  def normalize_incoming_value(value)
    case value
    when Array
      value.map { |item| normalize_incoming_value(item) }.compact_blank
    when ActionController::Parameters
      value.to_unsafe_h.transform_values { |item| normalize_incoming_value(item) }
    when Hash
      value.transform_values { |item| normalize_incoming_value(item) }
    else
      value.respond_to?(:original_filename) ? store_uploaded_module_file(value) : value
    end
  end

  def normalize_for_slug(data)
    case @module_slug
    when "training-form"
      normalize_training_form_data(data)
    when "add-farmer-form"
      normalize_add_farmer_form_data(data)
    when *OTHER_TARGET_SLUGS
      normalize_seed_distribution_target_data(data)
    else
      stamp_target_record_creator!(data)
      data
    end
  end

  def validation_errors(data)
    case @module_slug
    when "training-form"
      training_form_error_messages(data)
    when "add-farmer-form"
      add_farmer_form_error_messages(data)
    when *OTHER_TARGET_SLUGS
      seed_distribution_target_error_messages(data)
    else
      []
    end
  end

  def visible?(record)
    return true if admin_user?

    if vrp_login_user?
      return false unless current_vrp_record

      return target_record_matches_vrp?(record, current_vrp_record)
    end

    return true if created_by_current_user?(record)

    vrp = target_record_vrp_for_visibility(record)
    if vrp
      return true if vrp_registered_by_current_user?(vrp)
      return true if vrp_office_visible?(vrp)
      return true if cluster_visible_vrp_id_set.include?(vrp.id.to_s)
    end

    return false unless mapped_vrp_scope_active?

    # Asking "does this record match any of my Jeevika Jankars" one Jeevika
    # Jankar at a time compared every record against every one of them. The
    # answer is the same as asking whether the record carries any label they
    # go by, so the labels are collected once and looked up.
    labels = cluster_vrp_label_set
    record_visibility_values(record).any? { |value| labels.include?(value) }
  end

  def cluster_visible_vrp_id_set
    @cluster_visible_vrp_id_set ||= cluster_visible_vrp_ids.map(&:to_s).to_set
  end

  def cluster_vrp_label_set
    @cluster_vrp_label_set ||= cluster_visible_vrps.flat_map { |vrp| vrp_match_labels(vrp) }.to_set
  end

  def record_visibility_values(record)
    data = record.data
    [data["jeevika_jankar_id"], data["vrp_id"], data["jeevika_jankar_name"], data["vrp_name"],
     data["select_vrp"], data["trainer_contact"], data["trainer_name"], data["contact_number"],
     data["jeevika_jankar_contact"]].map { |value| normalize_text(value) }.reject(&:blank?)
  end

  def vrp_match_labels(vrp)
    [vrp.id, vrp.name, vrp.user_name, vrp.mobile_no,
     [vrp.name, vrp.mobile_no.presence].compact_blank.join(" - ")]
      .map { |value| normalize_text(value) }.reject(&:blank?)
  end

  def admin_user?
    current_app_user["user_type"].to_s.strip.casecmp("admin").zero?
  end

  def vrp_login_user?
    current_app_user["record_type"].to_s == "Vrp"
  end

  def current_vrp_record
    return @current_vrp_record if defined?(@current_vrp_record)
    return @current_vrp_record = nil unless model_ready?(:Vrp)

    user = current_app_user
    id_values = [user["id"], user["vrp_id"]].compact_blank.map(&:to_s).select { |value| value.match?(/\A\d+\z/) }
    user_names = [user["username"], user["user_name"], user["name"]].compact_blank.map { |value| value.to_s.strip.downcase }.uniq
    mobile_values = [user["mobile_no"], user["mobile"], user["phone"]].compact_blank.map { |value| value.to_s.gsub(/\D/, "").last(10) }.reject(&:blank?).uniq
    email = user["email"].to_s.strip.downcase

    vrp = Vrp.where(id: id_values).first if vrp_login_user? && id_values.any?
    vrp ||= Vrp.where("LOWER(user_name) IN (?)", user_names).first if user_names.any? && Vrp.column_names.include?("user_name")
    vrp ||= Vrp.where(mobile_no: mobile_values).first if mobile_values.any? && Vrp.column_names.include?("mobile_no")
    vrp ||= Vrp.where("LOWER(email) = ?", email).first if email.present? && Vrp.column_names.include?("email")
    vrp ||= Vrp.where(id: id_values).first if vrp.blank? && id_values.any?
    @current_vrp_record = vrp
  end

  def created_by_current_user?(record)
    data = record.data
    return true if creator_id_matches?(data)

    # The signed-in user's own labels do not change between records.
    current_values = current_user_visibility_values
    record_values = visibility_values(
      data["created_by_username"],
      data["created_by_name"],
      data["created_by_email"],
      data["trainer_name"],
      data["trainer_contact"]
    )
    (current_values & record_values).any?
  end

  def current_user_id_set
    @current_user_id_set ||= current_user_ids.map(&:to_s).to_set
  end

  # A login is a User, a Vrp or a new-user ModuleRecord, and those tables keep
  # separate id sequences - User 9 and Vrp 9 are different people. Comparing the
  # stored creator id alone therefore handed one person another's records.
  # stamp_target_record_creator! already writes the creator's type alongside the
  # id, so the id is only trusted together with it. The web screens guard this
  # the same way.
  def creator_id_matches?(data)
    creator_id = data["created_by_id"].to_s
    return false if creator_id.blank?

    creator_type = data["created_by_record_type"].to_s
    # Rows written before the type was stored keep the original comparison, so
    # this cannot take an older record away from whoever owns it today.
    return current_user_id_set.include?(creator_id) if creator_type.blank?
    return false unless creator_type.casecmp(current_app_user["record_type"].to_s).zero?

    current_user_id_set.include?(creator_id)
  end

  def current_user_visibility_values
    @current_user_visibility_values ||= visibility_values(
      current_app_user["username"], current_app_user["user_name"], current_app_user["name"],
      current_app_user["email"], current_app_user["mobile_no"]
    )
  end

  def target_record_vrp_for_visibility(record)
    return unless model_ready?(:Vrp)

    vrp_id = record.data["jeevika_jankar_id"].presence || record.data["vrp_id"].presence || record.data["select_vrp"].presence
    return @visibility_vrps_by_id[vrp_id.to_s] if defined?(@visibility_vrps_by_id)
    return Vrp.find_by(id: vrp_id) if vrp_id.present?

    nil
  end

  def target_record_matches_vrp?(record, vrp)
    values = [
      record.data["jeevika_jankar_id"],
      record.data["vrp_id"],
      record.data["jeevika_jankar_name"],
      record.data["vrp_name"],
      record.data["select_vrp"],
      record.data["trainer_contact"],
      record.data["trainer_name"],
      record.data["contact_number"],
      record.data["jeevika_jankar_contact"]
    ].map { |value| normalize_text(value) }.reject(&:blank?)
    return false if values.blank?

    labels = [
      vrp.id,
      vrp.name,
      vrp.user_name,
      vrp.mobile_no,
      [vrp.name, vrp.mobile_no.presence].compact_blank.join(" - ")
    ].map { |value| normalize_text(value) }.reject(&:blank?)

    (values & labels).any?
  end

  def vrp_registered_by_current_user?(vrp)
    current_ids = current_user_id_set
    return true if vrp.created_by_id.present? && current_ids.include?(vrp.created_by_id.to_s)
    return true if vrp.respond_to?(:user_id) && vrp.user_id.present? && current_ids.include?(vrp.user_id.to_s)

    false
  end

  def vrp_office_visible?(vrp)
    office_keys = @current_agreement_office_keys ||= AgreementVrpScope.user_office_keys(current_app_user)
    vrp_keys = [vrp.fcoc, vrp.to_name].filter_map do |office|
      AgreementVrpScope.office_key(office).presence
    end
    return true if office_keys.any? && (office_keys & vrp_keys).any?

    vrp_fcoc = visibility_values(vrp.fcoc)
    vrp_to = visibility_values(vrp.to_name)
    # The signed-in user's offices are the same for every record.
    current_fcoc = @current_office_fcoc ||= visibility_values(
      current_app_user["fcoc"],
      current_app_user["fcoc_name"],
      current_app_user["office_category"],
      current_app_user["parent_office"]
    )
    current_to = @current_office_to ||= visibility_values(
      current_app_user["to"],
      current_app_user["to_name"],
      current_app_user["sub_office_name"],
      current_app_user["office"],
      current_app_user["office_name"]
    )

    fcoc_matches = vrp_fcoc.any? && (vrp_fcoc & current_fcoc).any?
    to_matches = vrp_to.any? && (vrp_to & current_to).any?

    return fcoc_matches && to_matches if vrp_fcoc.any? && vrp_to.any?
    return fcoc_matches if vrp_fcoc.any?
    return to_matches if vrp_to.any?

    false
  end

  def mapped_vrp_scope_active?
    return false if vrp_login_user?

    cluster_incharge_login? || cluster_visible_vrps.any?
  end

  def cluster_incharge_login?
    return false if admin_user? || vrp_login_user?

    current_role = [current_app_user["role"], current_app_user["role_name"]].compact_blank.join(" ")
    current_role.downcase.include?("cluster")
  end

  def cluster_visible_vrp_ids
    cluster_visible_vrps.map(&:id)
  end

  def cluster_visible_vrps
    return @cluster_visible_vrps if defined?(@cluster_visible_vrps)
    return @cluster_visible_vrps = [] unless model_ready?(:Vrp)

    labels = cluster_labels
    return @cluster_visible_vrps = [] if labels.blank?

    @cluster_visible_vrps = Vrp.where.not(cluster_incharge: [nil, ""]).select do |vrp|
      labels.any? { |label| labels_match?(label, vrp.cluster_incharge) }
    end
  end

  def cluster_labels
    [
      current_app_user["name"],
      current_app_user["username"],
      current_app_user["user_name"]
    ].compact_blank.uniq
  end

  def labels_match?(expected, actual)
    left = normalize_user_label(expected)
    right = normalize_user_label(actual)
    return false if left.blank? || right.blank?

    left == right || left.include?(right) || right.include?(left)
  end

  def current_user_ids
    @current_user_ids ||= [current_app_user["id"]].compact.uniq
  end

  def visibility_values(*values)
    Array(values).flatten.compact_blank.map { |value| normalize_user_label(value) }.reject(&:blank?).uniq
  end

  def normalize_text(value)
    value.to_s.strip.downcase
  end

  def normalize_user_label(label)
    label.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def stamp_target_record_creator!(data)
    user = current_app_user
    data["created_by_record_type"] = data["created_by_record_type"].presence || user["record_type"].to_s
    data["created_by_id"] = data["created_by_id"].presence || user["id"].to_s
    data["created_by_username"] = data["created_by_username"].presence || user["username"].presence || user["user_name"].to_s
    data["created_by_name"] = data["created_by_name"].presence || user["name"].to_s
    data["created_by_email"] = data["created_by_email"].presence || user["email"].to_s
  end

  def normalize_training_form_data(data)
    stamp_target_record_creator!(data)
    trainer_name, trainer_contact = training_trainer_defaults
    data["trainer_name"] = trainer_name if data["trainer_name"].blank? && trainer_name.present?
    data["trainer_contact"] = trainer_contact if data["trainer_contact"].blank? && trainer_contact.present?
    data["fco_name"] = data["trainee_department"] if data["fco_name"].blank? && data["trainee_department"].present?
    data["trainee_department"] = data["fco_name"] if data["trainee_department"].blank? && data["fco_name"].present?
    data["fco_name"] = training_trainee_department_default if data["fco_name"].blank?
    data["trainee_department"] = data["fco_name"] if data["trainee_department"].blank? && data["fco_name"].present?
    data["cluster_coordinator_name"] = data["internal_trainer_name_1"] if data["cluster_coordinator_name"].blank? && data["internal_trainer_name_1"].present?
    data["internal_trainer_name_1"] = data["cluster_coordinator_name"] if data["internal_trainer_name_1"].blank? && data["cluster_coordinator_name"].present?
    data["agronomist_name"] = data["internal_trainer_name_2"] if data["agronomist_name"].blank? && data["internal_trainer_name_2"].present?
    data["agronomist_name"] = training_referred_by_name if data["agronomist_name"].blank? && training_referred_by_name.present?
    data["internal_trainer_name_2"] = data["agronomist_name"] if data["internal_trainer_name_2"].blank? && data["agronomist_name"].present?
    data["ics_block"] = data["ics_name"] if data["ics_block"].blank? && data["ics_name"].present?
    data["gram_name"] = data["village_name"] if data["gram_name"].blank? && data["village_name"].present?
    data["main_activity_type"] = data["main_activity_type"].presence || "Training"
    data["main_activity"] = data["main_activity"].presence || data["training_topic"].presence
    data["sub_activity"] = data["sub_activity"].presence || data["training_subject"].presence
    data["training_topic"] = data["main_activity"] if data["main_activity"].present?
    data["training_subject"] = data["sub_activity"] if data["sub_activity"].present?

    if (mapping = training_target_match(data))
      data["target_mapping_id"] = mapping[:target_mapping_id]
      data["jeevika_jankar_id"] = mapping[:vrp_id]
      data["jeevika_jankar_name"] = mapping[:jeevika_jankar_name]
      data["jeevika_jankar_contact"] = mapping[:contact_number]
      # Trainer identity belongs to the Jeevika Jankar whose target is being
      # reported, not to an admin/CC who happens to submit or edit the form.
      data["trainer_name"] = mapping[:jeevika_jankar_name] if mapping[:jeevika_jankar_name].present?
      data["trainer_contact"] = mapping[:contact_number] if mapping[:contact_number].present?
      data["main_activity_type"] = mapping[:main_activity_type]
    end

    selected_farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq
    if training_form_activity_scope_present?(data)
      pending_farmer_ids = pending_training_farmer_ids_for(data)
      selected_farmer_ids &= (pending_farmer_ids + retained_farmer_ids) unless pending_farmer_ids.nil?
    end
    data["selected_farmer_ids"] = selected_farmer_ids
    data["selected_farmer_names"] = training_farmer_names(selected_farmer_ids)
    data["farmer_count"] = selected_farmer_ids.size.to_s
    data["total_farmer_count"] = selected_farmer_ids.size.to_s
    data.delete("status")
    data
  end

  def normalize_seed_distribution_target_data(data)
    stamp_target_record_creator!(data)
    # The indicator type has to be the one the target was set up with, otherwise
    # the record cannot find the mapping it belongs to.
    data["main_activity_type"] = other_with_farmer_slug? ? "Other with Farmer" : "Other"
    data["training_topic"] = data["training_topic"].presence || data["main_activity"].presence
    data["training_subject"] = data["training_subject"].presence || data["sub_activity"].presence
    data["main_activity"] = data["training_topic"] if data["main_activity"].blank?
    data["sub_activity"] = data["training_subject"] if data["sub_activity"].blank?
    data["completion_date"] = data["completion_date"].presence || data["date"].presence || Date.current.to_s
    data["date"] = data["completion_date"]

    if (mapping = seed_distribution_target_match(data))
      data["target_mapping_id"] = mapping[:target_mapping_id]
      data["jeevika_jankar_id"] = mapping[:vrp_id]
      data["jeevika_jankar_name"] = mapping[:jeevika_jankar_name]
      data["contact_number"] = mapping[:contact_number]
      data["jeevika_jankar_contact"] = mapping[:contact_number]
      data["department"] = mapping[:department]
      data["fcoc_name"] = mapping[:department]
      data["main_activity_type"] = mapping[:main_activity_type]
      data["target"] = mapping[:target].to_s if data["target"].blank?
      data["main_activity"] = mapping[:training_topic]
      data["sub_activity"] = mapping[:training_subject]
      data["training_topic"] = mapping[:training_topic]
      data["training_subject"] = mapping[:training_subject]
    end

    selected_farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq
    if !generic_other_target? && data["target_mapping_id"].present?
      pending_farmer_ids = pending_other_target_farmer_ids_for(data["target_mapping_id"])
      selected_farmer_ids &= (pending_farmer_ids + retained_farmer_ids) unless pending_farmer_ids.nil?
    end
    data["selected_farmer_ids"] = selected_farmer_ids
    data["selected_farmer_names"] = training_farmer_names(selected_farmer_ids)
    # The count follows the farmer selection, but an edit that only changes some
    # fields does not carry that selection, and rewriting the count from the
    # farmers already on the record threw away the number the caller sent while
    # still answering 200. Where the two disagree the validation says so.
    if selected_farmer_ids.any? && (farmer_selection_submitted? || data["farmer_count"].blank?)
      data["farmer_count"] = selected_farmer_ids.size.to_s
    end

    data["achievement"] = numeric_string(data["achievement"]) if data["achievement"].present?
    data["target"] = numeric_string(data["target"]) if data["target"].present?
    data.delete("status")
    data
  end

  def normalize_add_farmer_form_data(data)
    stamp_target_record_creator!(data)

    mapping = add_farmer_form_mapping_for(data["target_mapping_id"])
    if mapping
      data["vrp_id"] = mapping[:vrp_id]
      data["jeevika_jankar_id"] = mapping[:vrp_id]
      data["jeevika_jankar_name"] = mapping[:jeevika_jankar_name]
      data["contact_number"] = mapping[:contact_number]
      data["fco_id"] = mapping[:fco_id]
      data["fco_name"] = mapping[:fco_name]
      data["ics_id"] = mapping[:ics_id]
      data["ics_name"] = mapping[:ics_name]
      data["village_id"] = mapping[:village_id]
      data["village_name"] = mapping[:village_name]
      data["mapped_village"] = mapping[:label]
      data["new_farmer_target"] = mapping[:target_quantity]
    end

    data.delete("selected_farmer_ids")
    data["no_farmer"] = whole_number_value(data["no_farmer"]).to_s if whole_number_value(data["no_farmer"])
    data
  end

  def training_form_error_messages(data)
    required_fields = {
      "month" => "Month",
      "ics_block" => "ICS Name",
      "gram_name" => "Village Name",
      "fco_name" => "FCO Name",
      "trainer_name" => "Trainer Name",
      "trainer_contact" => "Trainer Contact",
      "training_date" => "Training Date",
      "training_location" => "Training Location",
      "main_activity" => "Main Activity",
      "sub_activity" => "Sub Activity",
      "training_method" => "Training Method",
      "training_description" => "Training Description",
      "male_count" => "Male Count",
      "female_count" => "Female Count",
      "next_farmer_training_date" => "Next Farmer Training Date",
      "training_register_upload" => "Training Register Upload"
    }

    errors = missing_required_data_errors(data, required_fields)
    selected_farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq
    farmer_count = whole_number_value(data["farmer_count"].presence || "0")
    male_count = whole_number_value(data["male_count"])
    female_count = whole_number_value(data["female_count"])
    total_farmer_count = selected_farmer_ids.size

    errors << "Target Farmers select karein." if selected_farmer_ids.blank?
    errors << "AFL Farmer Count valid whole number hona chahiye." if farmer_count.nil?
    errors << "Male Count valid whole number hona chahiye." if male_count.nil?
    errors << "Female Count valid whole number hona chahiye." if female_count.nil?
    errors << "Total Farmer Count valid whole number hona chahiye." if total_farmer_count.nil?
    if farmer_count && selected_farmer_ids.any? && farmer_count != selected_farmer_ids.size
      errors << "AFL Farmer Count selected farmers ke count ke equal hona chahiye."
    end
    errors
  end

  def seed_distribution_target_error_messages(data)
    errors = missing_required_data_errors(
      data,
      "jeevika_jankar_name" => "Jeevika Jankar Name",
      "contact_number" => "Contact Number",
      "month" => "Month",
      "ics" => "ICS",
      "village" => "Village",
      "training_topic" => "Main Activity",
      "training_subject" => "Sub Activity",
      "completion_date" => "Completion Date",
      "target" => "Target",
      "achievement" => "Achievement"
    )

    target = decimal_value(data["target"])
    achievement = decimal_value(data["achievement"])
    errors << "Target valid number hona chahiye." if target.nil?
    errors << "Achievement valid number hona chahiye." if achievement.nil?
    errors << "Target zero se kam nahi ho sakta." if target && target.negative?
    errors << "Achievement zero se kam nahi ho sakta." if achievement && achievement.negative?
    errors << "Achievement Target se jyada nahi ho sakta." if target && achievement && achievement > target

    target_mapping = seed_distribution_target_match(data)
    new_farmer_target = target_mapping&.dig(:new_farmer_target)
    farmer_count = whole_number_value(data["farmer_count"])
    selected_farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq
    unless new_farmer_target || generic_other_target?
      errors << "Farmer Count required hai." if data["farmer_count"].blank?
      errors << "Mapped Farmers select karein." if selected_farmer_ids.blank?
      errors << "Farmer Count valid whole number hona chahiye." if farmer_count.nil?
      errors << "Farmer Count selected farmers ke count ke equal hona chahiye." if farmer_count && selected_farmer_ids.any? && farmer_count != selected_farmer_ids.size
      errors << "Farmer Count Target se jyada nahi ho sakta." if target && farmer_count && farmer_count > target
    end

    errors << ["Mapped Other activity target select karein.", target_mapping_mismatch(data)]
      .compact_blank.join(" ") if target_mapping.blank?
    errors << "Contact Number valid 10 digit hona chahiye." if data["contact_number"].present? && data["contact_number"].to_s.gsub(/\D/, "").length != 10
    errors
  end

  # On its own "select a mapped target" says nothing about why none was found,
  # which left a refused save with nowhere to go. Where the record names a
  # target, the fields that disagree with it are spelled out.
  def target_mapping_mismatch(data)
    mapping = retained_target_mapping
    return nil unless mapping

    differences = {
      "Month" => [data["month"], mapping[:month]],
      "ICS" => [data["ics"], mapping[:ics]],
      "Village" => [data["village"], mapping[:village]],
      "Main Activity" => [data["training_topic"].presence || data["main_activity"], mapping[:training_topic]],
      "Sub Activity" => [data["training_subject"].presence || data["sub_activity"], mapping[:training_subject]]
    }.filter_map do |label, (sent, expected)|
      next if normalize_text(sent) == normalize_text(expected)

      "#{label} is \"#{sent}\" but the mapped target has \"#{expected}\""
    end
    return nil if differences.empty?

    "#{differences.join('; ')}."
  end

  def generic_other_target?
    @module_slug == "other-target"
  end

  def other_with_farmer_slug?
    @module_slug == "other-target-with-farmer"
  end

  # Only indicators set up as "Other with Farmer" belong on that form, and the
  # plain Other Target screens keep every other non-training indicator. A target
  # also drops off once every farmer it was mapped against is done, even though
  # the village may still hold farmers outside that mapping.
  def other_target_slug_accepts?(main_activity_type, target)
    with_farmer = normalize_text(main_activity_type) == normalize_text("Other with Farmer")
    return !with_farmer unless other_with_farmer_slug?

    with_farmer && !other_with_farmer_target_exhausted?(target)
  end

  def other_with_farmer_target_exhausted?(target)
    mapped = target_farmer_ids(target)
    return false if mapped.blank?

    (mapped - other_target_completed_farmer_ids_for(target.id)).empty?
  end

  # A cluster incharge editing a training form raises a request for the
  # Agronomist on the web rather than writing straight to the record.  The app
  # has to go the same way, otherwise an edit from the phone would skip the
  # approval the same person cannot skip on the website.
  def training_edit_needs_approval?
    @module_slug == "training-form" && cluster_incharge_login?
  end

  def add_farmer_form_error_messages(data)
    errors = []
    mapping = add_farmer_form_mapping_for(data["target_mapping_id"])

    errors << "Mapped Village required hai." if mapping.blank?
    errors << "New Farmer Target required hai." if mapping.present? && data["new_farmer_target"].to_i != mapping[:target_quantity].to_i
    errors << "No. Farmer required hai." if data["no_farmer"].blank?
    errors << "No. Farmer valid whole number hona chahiye." if data["no_farmer"].present? && whole_number_value(data["no_farmer"]).nil?
    errors << "No. Farmer 0 se jyada hona chahiye." if whole_number_value(data["no_farmer"]) && whole_number_value(data["no_farmer"]).to_i <= 0
    errors
  end

  def training_target_mappings
    return @training_target_mappings if defined?(@training_target_mappings)
    return @training_target_mappings = [] unless model_ready?(:TargetMapping)

    activity_settings = main_activity_settings
    sub_activity_settings = sub_activity_settings_for(activity_settings)
    targets = filtered_training_target_scope.includes(:vrp)
      .order(:ics_name, :ics_id, :village_name, :village_id, :id).to_a
    @training_completion_months = targets.map { |target| normalize_text(target.month_name) }.uniq
    preload_training_mapping_farmers(targets)
    @training_target_mappings = targets.filter_map do |target|
      activity_setting = activity_setting_for(target, activity_settings, sub_activity_settings) || {}

      farmer_ids = training_target_farmer_ids(target)
      {
        target_mapping_id: target.id.to_s,
        vrp_id: target.vrp_id.to_s,
        jeevika_jankar_name: target.vrp&.name.presence || target.vrp&.user_name.presence || "Jeevika Jankar ##{target.vrp_id}",
        contact_number: target.vrp&.mobile_no.to_s.gsub(/\D/, "").last(10),
        fco_id: target.fco_id.to_s,
        fco_name: target.fco_name.presence || target.vrp&.fcoc.to_s,
        fpo_id: target.fco_id.to_s,
        fpo_name: target.fco_name.presence || target.vrp&.fcoc.to_s,
        department: target.vrp&.fcoc.to_s.strip,
        month: target.month_name.to_s.strip,
        ics: target.ics_name.presence || target.ics_id,
        village: target.village_name.presence || target.village_id,
        main_activity_type: activity_setting[:main_activity_type].presence || "Training",
        main_activity: target.main_activity_name.to_s.strip,
        sub_activity: target.activity_name.to_s.strip,
        new_farmer_target: new_farmer_target_mapping?(target),
        completed_farmer_ids: completed_training_farmer_ids_for(target, farmer_ids),
        farmers: training_farmers_for_ids(farmer_ids)
      }
    end
      .reject { |mapping| mapping[:ics].blank? && mapping[:village].blank? }
      .uniq
  end

  def filtered_training_target_scope
    scope = training_target_scope
    filters = @training_mapping_filters || {}
    { "month" => %w[month_name], "ics" => %w[ics_name ics_id],
      "village" => %w[village_name village_id], "main_activity" => %w[main_activity_name],
      "sub_activity" => %w[activity_name], "fco_id" => %w[fco_id],
      "fco_name" => %w[fco_name] }.each do |key, columns|
      value = filters[key].presence
      value ||= filters["fpo_id"] if key == "fco_id"
      value ||= filters["fpo_name"] if key == "fco_name"
      next if value.blank?

      predicates = columns.map { |column| "LOWER(TRIM(#{column}::text)) = :value" }
      scope = scope.where(predicates.join(" OR "), value: value.to_s.strip.downcase)
    end
    scope
  end

  def preload_training_mapping_farmers(targets)
    fallback_targets = targets.select { |target| target_farmer_ids(target).empty? }
    @training_ics_mappings = if fallback_targets.any? && model_ready?(:VrpIcsMapping)
      VrpIcsMapping.where(vrp_id: fallback_targets.map(&:vrp_id).uniq).to_a.group_by(&:vrp_id)
    else
      {}
    end
    @training_farmer_ids_by_target = {}
    needs_location = []
    targets.each do |target|
      ids = target_farmer_ids(target)
      ids = mapped_training_farmer_ids(target) if ids.empty?
      ids.empty? ? needs_location << target : @training_farmer_ids_by_target[target.id] = ids
    end
    if needs_location.any? && model_ready?(:Afl)
      # Index the farmer master once rather than scan it once per target.
      @training_location_index = Hash.new { |hash, key| hash[key] = [] }
      location_scope = Afl.all
      { %w[fco_id fco] => needs_location.flat_map { |t| location_tokens([t.fco_id, t.fco_name]) },
        %w[ics_id ics_name] => needs_location.flat_map { |t| location_tokens([t.ics_id, t.ics_name]) },
        %w[village_id village_name] => needs_location.flat_map { |t| location_tokens([t.village_id, t.village_name]) } }.each do |columns, tokens|
        predicates = columns.map { |column| "EXISTS (SELECT 1 FROM unnest(string_to_array(LOWER(COALESCE(#{column}, '')), '||')) token WHERE TRIM(token) IN (:tokens))" }
        location_scope = location_scope.where(predicates.join(" OR "), tokens: tokens.uniq)
      end
      location_scope.pluck(:id, :fco_id, :fco, :ics_id, :ics_name, :village_id, :village_name).each do |id, *location|
        location_tokens(location[0, 2]).product(location_tokens(location[2, 2]), location_tokens(location[4, 2])).each do |key|
          @training_location_index[key] << id.to_s
        end
      end
      needs_location.each { |target| @training_farmer_ids_by_target[target.id] = training_location_farmer_ids(target) }
    end
    ids = @training_farmer_ids_by_target.values.flatten.uniq
    @training_farmer_payloads = model_ready?(:Afl) ? Afl.where(id: ids).select(:id, :farmer_name, :village_name, :father_name, :tracenet_no, :mobile_no, :khasara_no).order(:farmer_name, :id).to_a.to_h { |farmer| [farmer.id.to_s, training_farmer_payload(farmer)] } : {}
  end

  def location_tokens(values)
    Array(values).compact_blank.flat_map { |value| value.to_s.split("||") }.map { |value| normalize_text(value) }.compact_blank.uniq
  end

  def training_target_month_options
    month_options_from(active_month_master_months + training_target_month_names)
  end

  def seed_distribution_target_month_options
    month_options_from(active_month_master_months + seed_distribution_target_month_names)
  end

  # The month list only needs the months of the targets that would reach the
  # form. Building every mapping first meant reading each target's Jeevika
  # Jankar and farmers to then throw all of it away.
  def training_target_month_names
    return training_target_mappings.map { |mapping| mapping[:month] } if defined?(@training_target_mappings)

    filtered_training_target_scope
      .pluck(:month_name, :ics_name, :ics_id, :village_name, :village_id)
      .filter_map do |month, ics_name, ics_id, village_name, village_id|
        # The mapping list drops a target with neither an ICS nor a village, so
        # its month must not appear here either.
        next if ics_name.blank? && ics_id.blank? && village_name.blank? && village_id.blank?

        month.to_s.strip
      end
  end

  def seed_distribution_target_month_names
    return seed_distribution_target_mappings.map { |mapping| mapping[:month] } if defined?(@seed_distribution_target_mappings)

    activity_settings = main_activity_settings
    sub_activity_settings = sub_activity_settings_for(activity_settings)

    training_target_scope.filter_map do |target|
      setting = activity_setting_for(target, activity_settings, sub_activity_settings)
      next unless setting.present? && !training_main_activity_type?(setting[:main_activity_type])
      next unless other_target_slug_accepts?(setting[:main_activity_type], target)
      next if target.ics_name.blank? && target.ics_id.blank? &&
        target.village_name.blank? && target.village_id.blank?

      target.month_name.to_s.strip
    end
  end

  def active_month_master_months
    return [] unless model_ready?(:ModuleRecord)

    ModuleRecord
      .where(module_slug: "month-master")
      .select { |record| active_module_record?(record) }
      .filter_map { |record| first_present_data(record, "month_name", "month", "name", "select_bill_month") }
  end

  def month_options_from(values)
    Array(values)
      .map(&:to_s)
      .map(&:strip)
      .reject(&:blank?)
      .uniq { |month| normalize_text(month) }
      .sort_by { |month| [month_sort_index(month), month] }
  end

  def first_present_data(record, *keys)
    data = record.respond_to?(:data) ? record.data : {}
    keys.find { |key| data[key].present? }&.then { |key| data[key] }
  end

  def month_sort_index(month)
    normalized = normalize_text(month)
    index = Date::MONTHNAMES.index { |name| normalize_text(name) == normalized }
    index || 99
  end

  def seed_distribution_target_mappings
    return @seed_distribution_target_mappings if defined?(@seed_distribution_target_mappings)
    return @seed_distribution_target_mappings = [] unless model_ready?(:TargetMapping)

    activity_settings = main_activity_settings
    sub_activity_settings = sub_activity_settings_for(activity_settings)

    # Every row reads the Jeevika Jankar for the name, contact and office, which
    # was one query per target.
    @seed_distribution_target_mappings = training_target_scope
      .includes(:vrp)
      .order(:ics_name, :ics_id, :village_name, :village_id, :id)
      .filter_map do |target|
        activity_setting = activity_setting_for(target, activity_settings, sub_activity_settings)
        next unless activity_setting.present? && !training_main_activity_type?(activity_setting[:main_activity_type])
        next unless other_target_slug_accepts?(activity_setting[:main_activity_type], target)

        farmer_ids = generic_other_target? ? [] : target_farmer_ids(target)
        {
          target_mapping_id: target.id.to_s,
          vrp_id: target.vrp_id.to_s,
          jeevika_jankar_name: target.vrp&.name.presence || target.vrp&.user_name.presence || "Jeevika Jankar ##{target.vrp_id}",
          contact_number: target.vrp&.mobile_no.to_s.gsub(/\D/, "").last(10),
          department: target.vrp&.fcoc.to_s.strip,
          month: target.month_name.to_s.strip,
          ics: target.ics_name.presence || target.ics_id,
          village: target.village_name.presence || target.village_id,
          main_activity_type: activity_setting[:main_activity_type].presence || "Other",
          training_topic: target.main_activity_name.to_s.strip,
          training_subject: target.activity_name.to_s.strip,
          main_activity: target.main_activity_name.to_s.strip,
          sub_activity: target.activity_name.to_s.strip,
          target: target.target_quantity.to_s,
          new_farmer_target: new_farmer_target_mapping?(target),
          completed_farmer_ids: generic_other_target? ? [] : other_target_completed_farmer_ids_for(target.id),
          farmers: generic_other_target? ? [] : training_farmers_for_ids(farmer_ids)
        }
      end
      .reject { |mapping| mapping[:ics].blank? && mapping[:village].blank? }
      .uniq
  end

  def add_farmer_form_mappings
    return @add_farmer_form_mappings if defined?(@add_farmer_form_mappings)
    return @add_farmer_form_mappings = [] unless model_ready?(:TargetMapping)

    scope = TargetMapping.includes(:vrp).order(:village_name, :village_id, :id)
      .select { |target| new_farmer_target_mapping?(target) }

    if vrp_login_user?
      vrp = current_vrp_record
      return @add_farmer_form_mappings = [] unless vrp

      scope = scope.select { |target| target.vrp_id.to_s == vrp.id.to_s }
    elsif !admin_user?
      visible_ids = add_farmer_visible_vrp_ids
      return @add_farmer_form_mappings = [] if visible_ids.blank?

      scope = scope.select { |target| visible_ids.include?(target.vrp_id.to_s) }
    end

    @add_farmer_form_mappings = scope.map { |target| add_farmer_mapping_payload(target) }
  end

  def add_farmer_form_mapping_for(mapping_id)
    add_farmer_form_mappings.find { |mapping| mapping[:id].to_s == mapping_id.to_s }
  end

  def add_farmer_visible_vrp_ids
    ids = cluster_visible_vrp_ids.map(&:to_s)
    current_ids = current_user_ids
    if current_ids.any? && model_ready?(:Vrp)
      scope = Vrp.where(created_by_id: current_ids)
      scope = scope.or(Vrp.where(user_id: current_ids)) if Vrp.column_names.include?("user_id")
      ids.concat(scope.pluck(:id).map(&:to_s))
    end
    ids.reject(&:blank?).uniq
  end

  def add_farmer_mapping_payload(target)
    village_label = target.village_name.presence || target.village_id.to_s
    vrp = target.vrp
    {
      id: target.id.to_s,
      vrp_id: target.vrp_id.to_s,
      jeevika_jankar_name: vrp&.name.presence || vrp&.user_name.presence || "Jeevika Jankar ##{target.vrp_id}",
      contact_number: vrp&.mobile_no.to_s.gsub(/\D/, "").last(10),
      fco_id: target.fco_id.to_s,
      fco_name: target.fco_name.to_s,
      ics_id: target.ics_id.to_s,
      ics_name: target.ics_name.to_s,
      village_id: target.village_id.to_s,
      village_name: target.village_name.to_s,
      label: village_label,
      target_quantity: target.target_quantity.to_i.to_s
    }
  end

  def current_seed_target_vrp_option
    return nil unless vrp_login_user? && current_vrp_record.present?

    {
      value: current_vrp_record.id.to_s,
      label: current_vrp_record.name.presence || current_vrp_record.user_name.presence || "Jeevika Jankar ##{current_vrp_record.id}",
      contact_number: current_vrp_record.mobile_no.to_s.gsub(/\D/, "").last(10),
      department: current_vrp_record.fcoc.to_s.strip
    }
  end

  def target_form_autofill
    vrp = current_vrp_record if vrp_login_user?
    department = training_trainee_department_default.presence || vrp&.fcoc.presence || current_app_user["fcoc"].presence || current_app_user["fcoc_name"].to_s
    trainer_name = vrp&.name.presence || current_app_user["name"].to_s
    trainer_contact = (vrp&.mobile_no.presence || current_app_user["mobile_no"]).to_s.gsub(/\D/, "").last(10)
    cluster_coordinator = vrp&.cluster_incharge.to_s
    agronomist = training_referred_by_name.to_s

    {
      jeevika_jankar_id: vrp&.id&.to_s,
      jeevika_jankar_name: vrp&.name.presence || current_app_user["name"].to_s,
      contact_number: trainer_contact,
      department: department,
      fco_name: department,
      trainee_department: department,
      trainer_name: trainer_name,
      trainer_contact: trainer_contact,
      cluster_coordinator_name: cluster_coordinator,
      internal_trainer_name_1: cluster_coordinator,
      agronomist_name: agronomist,
      internal_trainer_name_2: agronomist,
      papl_staff_name: current_app_user["name"].presence || current_app_user["username"].to_s,
      main_activity_type: "Training"
    }
  end

  def other_target_form_fields
    fields = [
      field_payload("jeevika_jankar_name", "Jeevika Jankar Name", "select", "jeevika_jankars"),
      field_payload("contact_number", "Contact Number", "tel", nil, readonly: true),
      field_payload("department", "FCO Name", "text", nil, readonly: true),
      field_payload("month", "Month", "select", "months"),
      field_payload("ics", "ICS", "select", "ics"),
      field_payload("village", "Village", "select", "villages"),
      field_payload("main_activity", "Main Activity", "select", "main_activities"),
      field_payload("sub_activity", "Sub Activity", "select", "sub_activities"),
      field_payload("completion_date", "Completion Date", "date"),
      field_payload("target", "Target", "number", nil, readonly: true),
      field_payload("achievement", "Achievement", "number"),
      field_payload("attachment_upload", "Attachment Upload", "file", nil, accept: ".pdf,.xlsx,.xls,.csv", multiple: generic_other_target?),
      field_payload("field_photo", "Field Photo", "file", nil, accept: "image/*", multiple: generic_other_target?)
    ]
    return fields if generic_other_target?

    fields.insert(9, field_payload("farmer_count", "Farmer Count", "number", nil, readonly: true))
  end

  def other_target_upload_constraints
    return {} unless generic_other_target?

    {
      attachment_upload: {
        max_files: 5,
        max_size_mb: 5,
        extensions: %w[.pdf .xlsx .xls .csv]
      },
      field_photo: {
        max_files: 5,
        max_size_mb: 5,
        content_type_prefix: "image/"
      }
    }
  end

  def training_form_fields
    [
      field_payload("month", "Month", "select", "months"),
      field_payload("ics_block", "ICS Name", "select", "ics"),
      field_payload("gram_name", "Village Name", "select", "villages"),
      field_payload("fco_name", "FCO Name", "text", nil, readonly: vrp_login_user?),
      field_payload("trainer_name", "Trainer Name", "text", nil, readonly: vrp_login_user?),
      field_payload("trainer_contact", "Trainer Contact", "tel", nil, readonly: vrp_login_user?),
      field_payload("cluster_coordinator_name", "Cluster Coordinator Name", "select", "cluster_coordinators", required: false),
      field_payload("agronomist_name", "Agronomist Name", "select", "agronomists", required: false),
      field_payload("papl_staff_name", "ASA Staff Name", "select", "papl_staff", required: false),
      field_payload("external_input", "Internal Inspector Name", "text", nil, required: false),
      field_payload("training_date", "Training Date", "date"),
      field_payload("training_location", "Training Location", "text"),
      field_payload("main_activity", "Main Major Work Indicator", "select", "main_activities"),
      field_payload("sub_activity", "Sub Major Work Indicator", "select", "sub_activities"),
      field_payload("training_method", "Training Method", "select", "training_methods"),
      field_payload("training_description", "Training Description", "text"),
      field_payload("farmer_count", "Farmer Count", "number", nil, readonly: true),
      field_payload("male_count", "Male Count", "number"),
      field_payload("female_count", "Female Count", "number"),
      field_payload("total_farmer_count", "Total Farmer Count", "number", nil, readonly: true),
      field_payload("other_farmer_count", "Other Farmer Count", "number", nil, required: false),
      field_payload("next_farmer_training_date", "Next Farmer Training Date", "date"),
      field_payload("training_register_upload", "Evidence/Documentation Pdf", "file", nil, accept: "application/pdf"),
      field_payload("training_photo_upload_with_geo_tag", "Training Photo Upload with Geo Tag", "file", nil, required: false, accept: "image/jpeg,image/png,image/webp,image/heic,image/heif", multiple: true),
      field_payload("photo_front_view", "Opening/Introduction Photo - Trainer", "file", nil, required: false, accept: "image/jpeg,image/png,image/webp,image/heic,image/heif", multiple: true),
      field_payload("photo_back_view", "Training Major Work Indicator Photo - Trainer", "file", nil, required: false, accept: "image/jpeg,image/png,image/webp,image/heic,image/heif", multiple: true),
      field_payload("photo_close_up_view", "Farmer Interaction Photo", "file", nil, required: false, accept: "image/jpeg,image/png,image/webp,image/heic,image/heif", multiple: true),
      field_payload("photo_long_shot", "Wide Group Photo", "file", nil, required: false, accept: "image/jpeg,image/png,image/webp,image/heic,image/heif", multiple: true),
      field_payload("selected_farmer_ids", "Target Farmers", "multi_select", "mapped_farmers")
    ]
  end

  def field_payload(key, label, type, options_key = nil, required: true, readonly: false, accept: nil, multiple: false)
    {
      key: key,
      label: label,
      type: type,
      options_key: options_key,
      required: required,
      readonly: readonly,
      accept: accept,
      multiple: multiple
    }.compact
  end

  def training_people_options
    {
      cluster_coordinators: cluster_coordinator_options,
      agronomists: agronomist_options,
      papl_staff: papl_staff_options
    }
  end

  def cluster_coordinator_options
    return training_people_options_for_current_vrp(:cluster_coordinator) if vrp_login_user?

    (registered_user_options_matching(/cluster/i) + registered_vrp_cluster_names)
      .compact_blank
      .uniq { |name| normalize_text(name) }
      .unshift("N/A")
      .uniq
  end

  def agronomist_options
    return training_people_options_for_current_vrp(:agronomist) if vrp_login_user?

    registered_user_options_matching(/agronomist/i)
      .compact_blank
      .uniq { |name| normalize_text(name) }
      .unshift("N/A")
      .uniq
  end

  def papl_staff_options
    (registered_app_user_names + registered_module_user_names)
      .compact_blank
      .select { |name| papl_staff_option_allowed?(name) }
      .uniq { |name| normalize_text(name) }
      .unshift("N/A")
      .uniq
  end

  def training_people_options_for_current_vrp(kind)
    values = ["N/A"]
    vrp = current_vrp_record

    case kind
    when :cluster_coordinator
      values << vrp&.cluster_incharge
    when :agronomist
      values << training_referred_by_name
    when :papl_staff
      values << current_app_user["name"].presence || current_app_user["username"]
    end

    values.map(&:to_s).map(&:strip).reject(&:blank?).uniq { |name| normalize_text(name) }
  end

  def registered_user_options_matching(pattern)
    (registered_app_user_rows_matching(pattern) + registered_module_user_rows_matching(pattern))
      .compact_blank
      .uniq { |name| normalize_text(name) }
  end

  ROLE_KEYS = %w[role role_name stakeholder_role user_management_role person_type].freeze

  # The three staff dropdowns each walked the whole user list, so one form read
  # the users and the new-user records three times over, with every column.
  def staff_users
    return @staff_users if defined?(@staff_users)
    return @staff_users = [] unless model_ready?(:User)

    columns = (%w[id first_name last_name user_name updated_at] + ROLE_KEYS) & User.column_names
    @staff_users = User.select(*columns).order(updated_at: :desc).to_a
  end

  def staff_module_users
    return @staff_module_users if defined?(@staff_module_users)
    return @staff_module_users = [] unless model_ready?(:ModuleRecord)

    @staff_module_users = ModuleRecord.where(module_slug: "new-user")
      .select(:id, :data).order(updated_at: :desc).select { |record| active_module_record?(record) }
  end

  def registered_app_user_rows_matching(pattern)
    staff_users.filter_map do |user|
      next unless ROLE_KEYS.any? { |key| user.try(key).to_s.match?(pattern) }

      user.full_name.presence || user.user_name.presence
    end
  end

  def registered_module_user_rows_matching(pattern)
    staff_module_users.filter_map do |record|
      next unless ROLE_KEYS.any? { |key| record.data[key].to_s.match?(pattern) }

      [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence || record.data["user_name"].presence
    end
  end

  def registered_vrp_cluster_names
    return [] unless model_ready?(:Vrp)
    return [] unless Vrp.column_names.include?("cluster_incharge")

    Vrp.order(updated_at: :desc).pluck(:cluster_incharge).compact_blank.uniq
  end

  def registered_app_user_names
    staff_users.filter_map { |user| user.full_name.presence || user.user_name.presence }
  end

  def registered_module_user_names
    staff_module_users.filter_map do |record|
      [record.data["first_name"], record.data["last_name"]].compact_blank.join(" ").presence || record.data["user_name"].presence
    end
  end

  def papl_staff_option_allowed?(name)
    normalized_name = normalize_text(name)
    normalized_name.present? && normalized_name != "admin"
  end

  def training_target_match(data)
    selected_month = normalize_text(data["month"])
    selected_ics = normalize_text(data["ics_name"].presence || data["ics_block"].presence || data["ics"])
    selected_village = normalize_text(data["village_name"].presence || data["gram_name"].presence || data["village"])
    selected_main_activities = normalized_text_values(data["main_activity"].presence || data["training_topic"])
    selected_sub_activities = normalized_text_values(data["sub_activity"].presence || data["training_subject"])

    training_target_mappings.find do |mapping|
      normalize_text(mapping[:month]) == selected_month &&
        normalize_text(mapping[:ics]) == selected_ics &&
        normalize_text(mapping[:village]) == selected_village &&
        selected_main_activities.include?(normalize_text(mapping[:main_activity])) &&
        selected_sub_activities.include?(normalize_text(mapping[:sub_activity]))
    end
  end

  def normalized_text_values(value)
    Array(value).flatten.map { |item| normalize_text(item) }.reject(&:blank?).uniq
  end

  def seed_distribution_target_match(data)
    selected_vrp = normalize_text(data["jeevika_jankar_id"].presence || data["jeevika_jankar_name"])
    selected_month = normalize_text(data["month"])
    selected_ics = normalize_text(data["ics"])
    selected_village = normalize_text(data["village"])
    selected_topic = normalize_text(data["training_topic"].presence || data["main_activity"])
    selected_subject = normalize_text(data["training_subject"].presence || data["sub_activity"])
    selected_main_activity_type = normalize_text(data["main_activity_type"])

    matches = lambda do |mapping|
      [mapping[:vrp_id], mapping[:jeevika_jankar_name]].any? { |value| normalize_text(value) == selected_vrp } &&
        (selected_main_activity_type.blank? || normalize_text(mapping[:main_activity_type]) == selected_main_activity_type) &&
        normalize_text(mapping[:month]) == selected_month &&
        normalize_text(mapping[:ics]) == selected_ics &&
        normalize_text(mapping[:village]) == selected_village &&
        normalize_text(mapping[:training_topic]) == selected_topic &&
        normalize_text(mapping[:training_subject]) == selected_subject
    end

    found = seed_distribution_target_mappings.find(&matches)
    return found if found

    # The list offered on a blank form only holds mappings whose main activity is
    # set up as non-Training, so a record saved before that setup changed cannot
    # find itself again and an edit of, say, the achievement would be refused.
    # The record already knows its mapping, so it is checked too - and only
    # accepted when the edit still describes that same mapping.
    retained = retained_target_mapping
    retained if retained && matches.call(retained)
  end

  def training_target_scope
    scope = TargetMapping.all
    scope = scope.where(vrp_id: current_vrp_record&.id) if vrp_login_user?
    if !admin_user? && !vrp_login_user?
      if cluster_incharge_login?
        scope = scope.where(vrp_id: cluster_visible_vrp_ids)
      elsif AgreementVrpScope.user_office_keys(current_app_user).any?
        offices = AgreementVrpScope.user_office_keys(current_app_user)
        ids = Vrp.select(:id, :fcoc).select { |vrp| offices.include?(AgreementVrpScope.office_key(vrp.fcoc)) }.map(&:id)
        scope = scope.where(vrp_id: ids)
      elsif mapped_vrp_scope_active?
        scope = scope.where(vrp_id: cluster_visible_vrp_ids)
      else
        scope = scope.none
      end
    end
    scope
  end

  def training_trainer_defaults
    if vrp_login_user? && current_vrp_record.present?
      return [current_vrp_record.name, current_vrp_record.mobile_no]
    end

    [current_app_user["name"], current_app_user["mobile_no"]]
  end

  def training_trainee_department_default
    [
      current_vrp_record&.fcoc,
      current_app_user["fcoc"],
      current_app_user["fcoc_name"]
    ].compact_blank.first.to_s
  end

  def training_referred_by_name
    @training_referred_by_name ||= begin
      vrp = current_vrp_record
      creator = training_vrp_creator(vrp)
      training_creator_name(creator).presence
    end
  end

  def training_vrp_creator(vrp)
    return nil unless vrp&.created_by_id.present?

    if vrp.respond_to?(:created_by_type) && vrp.created_by_type.present?
      return User.find_by(id: vrp.created_by_id) if vrp.created_by_type == "User" && model_ready?(:User)
      return ModuleRecord.find_by(id: vrp.created_by_id) if vrp.created_by_type == "ModuleRecord" && model_ready?(:ModuleRecord)
    end

    (model_ready?(:User) && User.find_by(id: vrp.created_by_id)) ||
      (model_ready?(:ModuleRecord) && ModuleRecord.find_by(id: vrp.created_by_id))
  end

  def training_creator_name(creator)
    return "" unless creator
    return creator.full_name.presence || creator.user_name.to_s if creator.respond_to?(:full_name)

    data = creator.respond_to?(:data) ? creator.data : {}
    [data["first_name"], data["last_name"]].compact_blank.join(" ").presence ||
      data["name"].presence ||
      data["user_name"].to_s
  end

  # "Pending" means a farmer no other record has trained yet, which is the right
  # test when a form is first filled in.  On an edit the farmers already on the
  # record are not up for grabs — they are this record's own — so they stay
  # selectable and an edit of some other field cannot quietly drop them.
  def retained_farmer_ids
    @retained_farmer_ids || []
  end

  # A save carries the whole form; an edit only carries what changed.
  def farmer_selection_submitted?
    @farmer_selection_submitted.nil? || @farmer_selection_submitted
  end

  # The mapping the record being edited was saved against, shaped like the ones
  # the blank form offers so it can be compared the same way.
  def retained_target_mapping
    return @retained_target_mapping if defined?(@retained_target_mapping)
    return @retained_target_mapping = nil if @retained_target_mapping_id.blank?
    return @retained_target_mapping = nil unless model_ready?(:TargetMapping)

    target = TargetMapping.find_by(id: @retained_target_mapping_id)
    return @retained_target_mapping = nil unless target

    @retained_target_mapping = {
      target_mapping_id: target.id.to_s,
      vrp_id: target.vrp_id.to_s,
      jeevika_jankar_name: target.vrp&.name.presence || target.vrp&.user_name.presence || "Jeevika Jankar ##{target.vrp_id}",
      contact_number: target.vrp&.mobile_no.to_s.gsub(/\D/, "").last(10),
      department: target.vrp&.fcoc.to_s.strip,
      month: target.month_name.to_s.strip,
      ics: target.ics_name.presence || target.ics_id,
      village: target.village_name.presence || target.village_id,
      main_activity_type: other_with_farmer_slug? ? "Other with Farmer" : "Other",
      training_topic: target.main_activity_name.to_s.strip,
      training_subject: target.activity_name.to_s.strip,
      main_activity: target.main_activity_name.to_s.strip,
      sub_activity: target.activity_name.to_s.strip,
      target: target.target_quantity.to_s,
      new_farmer_target: new_farmer_target_mapping?(target),
      completed_farmer_ids: generic_other_target? ? [] : other_target_completed_farmer_ids_for(target.id),
      farmers: generic_other_target? ? [] : training_farmers_for_ids(target_farmer_ids(target))
    }
  end

  def training_form_activity_scope_present?(data)
    data["month"].present? &&
      (data["village_name"].present? || data["gram_name"].present?) &&
      data["main_activity"].present? &&
      data["sub_activity"].present?
  end

  def target_village_ids(target)
    return [] unless target.respond_to?(:village_id)

    raw = target.village_id
    values = raw.is_a?(String) && raw.strip.start_with?("[") ? (JSON.parse(raw) rescue []) : Array(raw)
    values.flatten
      .flat_map { |value| value.to_s.split(",") }
      .map { |value| value.to_s.split("||").first.to_s.strip }
      .compact_blank
      .uniq
  end

  def local_village_farmer_ids(village_ids)
    return [] if village_ids.blank? || !model_ready?(:Afl)

    Afl.where(village_id: village_ids).pluck(:id).map(&:to_s)
  end

  # Farmers that only live in the external register have no Afl row, so they
  # come back blank; their details are filled in from the village feed.
  def resolve_live_farmer_details(live_ids, mapped_ids, village_ids)
    mapped = mapped_ids.map(&:to_s).to_set
    known = model_ready?(:Afl) ? Afl.where(id: live_ids).index_by { |farmer| farmer.id.to_s } : {}
    external = external_village_farmer_details(village_ids)

    live_ids.map do |id|
      row = if (farmer = known[id])
        training_farmer_payload(farmer)
      else
        details = external[id] || {}
        { id: id, farmer_name: details[:farmer_name].presence || "Farmer ##{id}",
          village_name: details[:village_name].to_s, father_name: details[:father_name].to_s,
          tracenet_no: details[:tracenet_no].to_s, mobile_no: details[:mobile_no].to_s,
          khasara_no: details[:khasara_no].to_s }
      end
      # The screen marks who the target was mapped against, so the count of
      # "target" farmers and "other village" farmers can be shown apart.
      row.merge(is_target: mapped.include?(id))
    end.sort_by { |row| [row[:is_target] ? 0 : 1, row[:farmer_name].to_s.downcase, row[:id].to_i] }
  end

  # Shares the cache the web screen already fills, so a village looked up on
  # either side is not fetched twice.
  def external_village_farmer_details(village_ids)
    village_ids = Array(village_ids).map(&:to_s).compact_blank.uniq
    return {} if village_ids.blank?

    village_ids.each_with_object({}) do |village_id, memo|
      cached = Rails.cache.fetch(["training-village-farmer-details", village_id], expires_in: 5.minutes) do
        fetch_external_village_farmers(village_id)
      end
      memo.merge!(cached || {})
    end
  end

  def fetch_external_village_farmers(village_id)
    uri = URI("https://asa.ploughmanagro.com/api/farmers/get_farmers.json")
    rows = []
    page = 1
    loop do
      uri.query = URI.encode_www_form(data_type: "detail", type: "village",
        village_id: village_id, page: page, per_page: 500)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 4,
        read_timeout: 12) { |http| http.get(uri.request_uri) }
      break unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      break if payload["success"] == false

      page_rows = Array(payload["data"])
      rows.concat(page_rows)
      break if page_rows.empty? || rows.size >= Integer(payload["count"])

      page += 1
    end
    rows.each_with_object({}) do |row, memo|
      farmer = row["farmer"].is_a?(Hash) ? row["farmer"] : row
      id = (farmer["farmer_unique_id"].presence || farmer["id"].presence).to_s
      next if id.blank?

      memo[id] ||= {
        village_name: farmer["village_name"].presence || row.dig("address", "village").presence || row.dig("grouping", "village"),
        farmer_name: farmer["farmer_name"].to_s.strip.presence || "Farmer ##{id}",
        father_name: farmer["father_husband_name"].presence || farmer["father_name"].presence,
        tracenet_no: farmer["tracenet_id"].presence || farmer["tracenet_no"].presence,
        mobile_no: farmer["mobile_no"].presence,
        khasara_no: Array(row["lands"]).filter_map { |land| land["khasra_no"].presence || land["plot_no"].presence }.join(", ").presence
      }
    end
  rescue StandardError => error
    Rails.logger.warn("External village farmer fetch for village #{village_id}: #{error.class} - #{error.message}")
    {}
  end

  def pending_training_farmer_ids_for(data)
    return nil unless model_ready?(:TargetMapping)

    selected_month = normalize_text(data["month"])
    selected_ics = normalize_text(data["ics_name"].presence || data["ics_block"])
    selected_village = normalize_text(data["village_name"].presence || data["gram_name"])
    selected_main_activity_type = normalize_text(data["main_activity_type"])
    selected_main_activities = normalized_text_values(data["main_activity"])
    selected_sub_activities = normalized_text_values(data["sub_activity"])
    activity_settings = main_activity_settings

    training_target_scope.each_with_object([]) do |target, ids|
      activity_setting = activity_settings[normalize_text(target.main_activity_name)] || {}

      target_main_activity_type = normalize_text(activity_setting[:main_activity_type].presence || "Training")
      next if normalize_text(target.month_name) != selected_month
      next if selected_ics.present? && normalize_text(target.ics_name.presence || target.ics_id) != selected_ics
      next if normalize_text(target.village_name.presence || target.village_id) != selected_village
      next unless selected_main_activities.include?(normalize_text(target.main_activity_name))
      next unless selected_sub_activities.include?(normalize_text(target.activity_name))

      farmer_ids = Array(target.afl_ids).map(&:to_s).reject(&:blank?).uniq
      ids.concat(farmer_ids - completed_training_farmer_ids_for(target, farmer_ids))
    end.uniq
  end

  def pending_other_target_farmer_ids_for(target_mapping_id)
    return nil unless model_ready?(:TargetMapping)

    target = TargetMapping.find_by(id: target_mapping_id)
    return [] unless target

    target_farmer_ids(target) - other_target_completed_farmer_ids_for(target.id)
  end

  def other_target_completed_farmer_ids_for(target_mapping_id)
    return [] unless model_ready?(:ModuleRecord)

    target = model_ready?(:TargetMapping) ? TargetMapping.find_by(id: target_mapping_id) : nil
    mapped_farmer_ids = target ? target_farmer_ids(target) : nil

    ModuleRecord
      .where(module_slug: @module_slug)
      .order(created_at: :asc)
      .reject { |record| @exclude_record_id.present? && record.id.to_s == @exclude_record_id.to_s }
      .select { |record| blocking_other_target_record?(record) }
      .select { |record| record.data["target_mapping_id"].to_s == target_mapping_id.to_s }
      .flat_map { |record| Array(record.data["selected_farmer_ids"]).map(&:to_s) }
      .reject(&:blank?)
      .uniq
      .then { |ids| mapped_farmer_ids.present? ? (ids & mapped_farmer_ids) : ids }
  end

  def blocking_other_target_record?(record)
    return false if truthy_flag?(record.data["deleted"]) || truthy_flag?(record.data["is_deleted"]) || truthy_flag?(record.data["discarded"])

    status = record.data["approval_status"].presence || record.data["approval_state"].presence || record.data["status"].presence
    return true if status.blank?

    normalized_status = normalize_text(status)
    return false if normalized_status.include?("reject") || normalized_status.include?("return") || normalized_status == "inactive"

    true
  end

  def completed_training_farmer_ids_for(target, farmer_ids)
    farmer_ids = Array(farmer_ids).map(&:to_s).reject(&:blank?).uniq
    return [] if farmer_ids.blank?

    key = training_activity_key(target.month_name, target.main_activity_name, target.activity_name)
    completed = training_completion_index[key]
    farmer_ids.select { |id| completed.include?(id) }
  end

  def training_completion_index
    return @training_completion_index if defined?(@training_completion_index)

    @training_completion_index = Hash.new { |hash, key| hash[key] = Set.new }
    return @training_completion_index unless model_ready?(:ModuleRecord)

    completion_scope = ModuleRecord.where(module_slug: "training-form")
    if defined?(@training_completion_months)
      completion_scope = completion_scope.where("LOWER(TRIM(COALESCE(data::jsonb ->> 'month', ''))) IN (?)", @training_completion_months)
    end
    completion_scope.select(:id, :data).find_each do |record|
      next unless active_module_record?(record)
      next if @exclude_record_id.present? && record.id.to_s == @exclude_record_id.to_s

      summary = {
        month: record.data["month"],
        training_topic: record.data["main_activity"].presence || record.data["training_topic"],
        training_subject: record.data["sub_activity"].presence || record.data["training_subject"]
      }
      key = training_activity_key(summary[:month], summary[:training_topic], summary[:training_subject])
      next if key.all?(&:blank?)

      @training_completion_index[key].merge(Array(record.data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?))
    end

    @training_completion_index
  end

  def training_activity_key(month, main_activity, sub_activity = nil)
    [normalize_text(month), normalize_text(main_activity), normalize_text(sub_activity)]
  end

  def training_farmers_for_ids(farmer_ids)
    return [] unless model_ready?(:Afl)

    farmer_ids = Array(farmer_ids).map(&:to_s).reject(&:blank?).uniq
    return [] if farmer_ids.blank?

    if defined?(@training_farmer_payloads)
      return farmer_ids.filter_map { |id| @training_farmer_payloads[id] }.sort_by { |farmer| [farmer[:farmer_name], farmer[:id].to_i] }
    end
    Afl.where(id: farmer_ids).order(:farmer_name, :id).map { |farmer| training_farmer_payload(farmer) }
  end

  def training_farmer_payload(farmer)
    { id: farmer.id.to_s, farmer_name: farmer.farmer_name.presence || "Farmer ##{farmer.id}",
      village_name: farmer.village_name.to_s, father_name: farmer.father_name.to_s,
      tracenet_no: farmer.tracenet_no.to_s, mobile_no: farmer.mobile_no.to_s,
      khasara_no: farmer.khasara_no.to_s }
  end

  def training_target_farmer_ids(target)
    return @training_farmer_ids_by_target.fetch(target.id, []) if defined?(@training_farmer_ids_by_target)
    saved_ids = Array(target.afl_ids).map(&:to_s).reject(&:blank?).uniq
    return saved_ids if saved_ids.any?

    mapped_ids = mapped_training_farmer_ids(target)
    return mapped_ids if mapped_ids.any?

    training_location_farmer_ids(target)
  end

  def mapped_training_farmer_ids(target)
    return [] unless model_ready?(:VrpIcsMapping)

    mappings = defined?(@training_ics_mappings) ? Array(@training_ics_mappings[target.vrp_id]) : VrpIcsMapping.where(vrp_id: target.vrp_id)
    mappings.select do |mapping|
      training_location_matches?(mapping.fco_id, mapping.fco_name, target.fco_id, target.fco_name) &&
        training_location_matches?(mapping.ics_id, mapping.ics_name, target.ics_id, target.ics_name) &&
        training_location_matches?(mapping.village_id, mapping.village_name, target.village_id, target.village_name)
    end.flat_map { |mapping| Array(mapping.afl_ids).map(&:to_s) }.reject(&:blank?).uniq
  end

  def training_location_farmer_ids(target)
    if defined?(@training_location_index)
      return location_tokens([target.fco_id, target.fco_name])
        .product(location_tokens([target.ics_id, target.ics_name]), location_tokens([target.village_id, target.village_name]))
        .flat_map { |key| @training_location_index[key] }.uniq
    end
    return [] unless model_ready?(:Afl)

    Afl.all.select do |farmer|
      training_location_matches?(farmer.fco_id, farmer.fco, target.fco_id, target.fco_name) &&
        training_location_matches?(farmer.ics_id, farmer.ics_name, target.ics_id, target.ics_name) &&
        training_location_matches?(farmer.village_id, farmer.village_name, target.village_id, target.village_name)
    end.map { |farmer| farmer.id.to_s }.uniq
  end

  def training_location_matches?(left_id, left_name, right_id, right_name)
    left = [left_id, left_name].compact_blank.flat_map { |value| value.to_s.split("||") }.map { |value| normalize_text(value) }.reject(&:blank?)
    right = [right_id, right_name].compact_blank.flat_map { |value| value.to_s.split("||") }.map { |value| normalize_text(value) }.reject(&:blank?)
    left.any? && right.any? && (left & right).any?
  end

  def training_farmer_names(farmer_ids)
    training_farmers_for_ids(farmer_ids).map { |farmer| farmer[:farmer_name] }
  end

  def training_total_farmer_count(data)
    male_count = whole_number_value(data["male_count"])
    female_count = whole_number_value(data["female_count"])
    return nil unless male_count && female_count

    male_count + female_count
  end

  def target_farmer_ids(target)
    Array(target.respond_to?(:afl_ids) ? target.afl_ids : []).map(&:to_s).reject(&:blank?).uniq
  end

  def new_farmer_target_mapping?(target)
    target_farmer_ids(target).blank? && target.target_quantity.to_f.positive?
  end

  def main_activity_settings
    return {} unless model_ready?(:ModuleRecord)

    ModuleRecord.where(module_slug: "add-activity-group").order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .each_with_object({}) do |record, settings|
        name = normalize_text(record.data["main_activity_name"].presence || record.data["activity_group_name"])
        next if name.blank? || settings.key?(name)

        settings[name] = {
          main_activity_name: record.data["main_activity_name"].presence || record.data["activity_group_name"],
          main_activity_type: record.data["main_activity_type"].presence || "Training"
        }
      end
  end

  def sub_activity_settings_for(activity_settings)
    return {} unless model_ready?(:ModuleRecord)

    ModuleRecord.where(module_slug: "add-vrp-activity").order(created_at: :desc)
      .select { |record| active_module_record?(record) }
      .each_with_object({}) do |record, settings|
        main_key = normalize_text(record.data["main_activity"].presence || record.data["activity_group"])
        sub_key = normalize_text(record.data["sub_activity_name"].presence || record.data["activity_name"])
        next if main_key.blank? || sub_key.blank? || settings.key?(sub_key)

        settings[sub_key] = activity_settings[main_key] if activity_settings[main_key].present?
      end
  end

  def activity_setting_for(target, activity_settings, sub_activity_settings)
    main_key = normalize_text(target.main_activity_name)
    sub_key = normalize_text(target.activity_name)
    activity_settings[main_key] || activity_settings[sub_key] || sub_activity_settings[sub_key] || sub_activity_settings[main_key]
  end

  def training_main_activity_type?(value)
    normalize_text(value.presence || "Training") == normalize_text("Training")
  end

  def active_module_record?(record)
    return false if truthy_flag?(record.data["deleted"]) || truthy_flag?(record.data["is_deleted"]) || truthy_flag?(record.data["discarded"])

    status = record.data["status"].to_s.strip
    return true if status.blank?

    status.casecmp("Active").zero?
  end

  def truthy_flag?(value)
    %w[1 true yes deleted].include?(value.to_s.strip.downcase)
  end

  def missing_required_data_errors(data, fields)
    fields.filter_map { |key, label| "#{label} required hai." if data[key].blank? }
  end

  def whole_number_value(value)
    string = value.to_s.strip
    return nil if string.blank? || !string.match?(/\A\d+\z/)

    string.to_i
  end

  def decimal_value(value)
    string = value.to_s.strip
    return nil if string.blank?

    BigDecimal(string)
  rescue ArgumentError
    nil
  end

  def numeric_string(value)
    number = value.to_s.gsub(",", "").to_f
    number == number.to_i ? number.to_i.to_s : number.to_s
  end

  def store_uploaded_module_file(upload)
    upload_dir = Rails.root.join("public", "uploads", "module_records")
    FileUtils.mkdir_p(upload_dir)

    extension = File.extname(upload.original_filename)
    basename = File.basename(upload.original_filename, extension).parameterize
    filename = "#{Time.current.to_i}-#{SecureRandom.hex(4)}-#{basename}#{extension.downcase}"
    path = upload_dir.join(filename)

    if upload.respond_to?(:tempfile) && upload.tempfile
      upload.tempfile.rewind
      IO.copy_stream(upload.tempfile, path)
    else
      File.binwrite(path, upload.read)
    end
    "/uploads/module_records/#{filename}"
  end

  def training_photo_upload_errors(raw_attrs)
    return [] unless @module_slug == "training-form"

    raw = raw_attrs.respond_to?(:to_unsafe_h) ? raw_attrs.to_unsafe_h : Hash(raw_attrs)
    uploads = TRAINING_PHOTO_UPLOAD_KEYS.flat_map { |key| Array(raw[key] || raw[key.to_sym]) }.compact_blank
    uploads.each_with_object([]) do |upload, errors|
      next unless upload.respond_to?(:original_filename)

      unless TRAINING_PHOTO_CONTENT_TYPES.include?(upload.content_type.to_s.downcase)
        errors << "Training photos must be JPEG, PNG, WEBP, HEIC, or HEIF images."
      end
      if upload.respond_to?(:size) && upload.size.to_i > MAX_TRAINING_PHOTO_SIZE
        errors << "Each training photo must be 5 MB or smaller."
      end
    end.uniq
  end

  def other_target_upload_errors(raw_attrs)
    return [] unless generic_other_target?

    raw = raw_attrs.respond_to?(:to_unsafe_h) ? raw_attrs.to_unsafe_h : Hash(raw_attrs)
    other_target_upload_field_errors(raw["attachment_upload"] || raw[:attachment_upload], "Attachment Upload", attachment: true) +
      other_target_upload_field_errors(raw["field_photo"] || raw[:field_photo], "Field Photo")
  end

  def other_target_upload_field_errors(value, label, attachment: false)
    uploads = Array(value).flatten.filter_map { |upload| upload if upload.respond_to?(:original_filename) }
    errors = []
    errors << "#{label}: maximum 5 files are allowed." if uploads.size > 5
    errors << "#{label}: maximum file size is 5 MB." if uploads.any? { |upload| upload.respond_to?(:size) && upload.size.to_i > 5.megabytes }
    if attachment && uploads.any? { |upload| %w[.pdf .xlsx .xls .csv].exclude?(File.extname(upload.original_filename).downcase) }
      errors << "#{label}: only PDF or Excel files are allowed."
    end
    errors.uniq
  end

  def model_ready?(name)
    klass = name.to_s.safe_constantize
    klass.present? && (!klass.respond_to?(:table_exists?) || klass.table_exists?)
  end
end
