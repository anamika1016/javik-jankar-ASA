# frozen_string_literal: true

# Farmer Target module APIs for React Native.
# Stores ModuleRecord rows with the same slugs as the web UI (ModulesController untouched).
class FarmerTargetApi
  MAX_TRAINING_PHOTO_SIZE = 5.megabytes
  TRAINING_PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  OTHER_TARGET_SLUGS = %w[seed-distribution-target papl360-target].freeze
  TARGET_SLUGS = (%w[training-form add-farmer-form] + OTHER_TARGET_SLUGS).freeze

  def initialize(current_app_user:, module_slug:, exclude_record_id: nil)
    @current_app_user = current_app_user || {}
    @module_slug = module_slug.to_s
    @exclude_record_id = exclude_record_id
  end

  def list
    ModuleRecord
      .where(module_slug: @module_slug)
      .order(created_at: :desc)
      .select { |record| visible?(record) }
      .map { |record| record_payload(record) }
  end

  def find(id)
    record = ModuleRecord.find_by(id: id, module_slug: @module_slug)
    return nil unless record && visible?(record)

    record
  end

  def create(raw_attrs)
    upload_errors = training_photo_upload_errors(raw_attrs)
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

  def form_options
    case @module_slug
    when "training-form"
      {
        autofill: target_form_autofill,
        current_vrp: current_seed_target_vrp_option,
        months: training_target_mappings.map { |m| m[:month] }.compact_blank.uniq,
        target_mappings: training_target_mappings,
        training_methods: ["Input Demo INM", "Input Demo PM", "FFS", "OPG Training"]
      }
    when *OTHER_TARGET_SLUGS
      {
        autofill: target_form_autofill,
        months: seed_distribution_target_mappings.map { |m| m[:month] }.compact_blank.uniq,
        target_mappings: seed_distribution_target_mappings,
        current_vrp: current_seed_target_vrp_option
      }
    when "add-farmer-form"
      {
        mappings: add_farmer_form_mappings
      }
    else
      {}
    end
  end

  def record_payload(record)
    payload = {
      id: record.id,
      module_slug: record.module_slug,
      created_at: record.created_at,
      updated_at: record.updated_at,
      data: record.data
    }
    if record.module_slug == "training-form"
      payload[:photo_count] = Array(record.data["training_photo_upload_with_geo_tag"]).compact_blank.size
    end
    payload
  end

  private

  attr_reader :current_app_user

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
      return true if cluster_visible_vrp_ids.map(&:to_s).include?(vrp.id.to_s)
    end

    return false unless mapped_vrp_scope_active?

    cluster_visible_vrps.any? { |visible_vrp| target_record_matches_vrp?(record, visible_vrp) }
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
    current_ids = current_user_ids.map(&:to_s)
    return true if data["created_by_id"].present? && current_ids.include?(data["created_by_id"].to_s)

    current_values = visibility_values(
      current_app_user["username"],
      current_app_user["user_name"],
      current_app_user["name"],
      current_app_user["email"],
      current_app_user["mobile_no"]
    )
    record_values = visibility_values(
      data["created_by_username"],
      data["created_by_name"],
      data["created_by_email"],
      data["trainer_name"],
      data["trainer_contact"]
    )
    (current_values & record_values).any?
  end

  def target_record_vrp_for_visibility(record)
    return unless model_ready?(:Vrp)

    vrp_id = record.data["jeevika_jankar_id"].presence || record.data["vrp_id"].presence || record.data["select_vrp"].presence
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
    current_ids = current_user_ids.map(&:to_s)
    return true if vrp.created_by_id.present? && current_ids.include?(vrp.created_by_id.to_s)
    return true if vrp.respond_to?(:user_id) && vrp.user_id.present? && current_ids.include?(vrp.user_id.to_s)

    false
  end

  def vrp_office_visible?(vrp)
    vrp_fcoc = visibility_values(vrp.fcoc)
    vrp_to = visibility_values(vrp.to_name)
    current_fcoc = visibility_values(
      current_app_user["fcoc"],
      current_app_user["fcoc_name"],
      current_app_user["office_category"],
      current_app_user["parent_office"]
    )
    current_to = visibility_values(
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
    data["trainer_name"] = trainer_name if trainer_name.present?
    data["trainer_contact"] = trainer_contact if trainer_contact.present?
    data["trainee_department"] = training_trainee_department_default if data["trainee_department"].blank?
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
      data["main_activity_type"] = mapping[:main_activity_type]
    end

    selected_farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq
    if training_form_activity_scope_present?(data)
      pending_farmer_ids = pending_training_farmer_ids_for(data)
      selected_farmer_ids &= pending_farmer_ids unless pending_farmer_ids.nil?
    end
    data["selected_farmer_ids"] = selected_farmer_ids
    data["selected_farmer_names"] = training_farmer_names(selected_farmer_ids)
    data["farmer_count"] = selected_farmer_ids.size.to_s
    total = training_total_farmer_count(data)
    data["total_farmer_count"] = total.to_s if total
    data.delete("status")
    data
  end

  def normalize_seed_distribution_target_data(data)
    stamp_target_record_creator!(data)
    data["main_activity_type"] = "Other"
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
    if data["target_mapping_id"].present?
      pending_farmer_ids = pending_other_target_farmer_ids_for(data["target_mapping_id"])
      selected_farmer_ids &= pending_farmer_ids unless pending_farmer_ids.nil?
    end
    data["selected_farmer_ids"] = selected_farmer_ids
    data["selected_farmer_names"] = training_farmer_names(selected_farmer_ids)
    data["farmer_count"] = selected_farmer_ids.size.to_s if selected_farmer_ids.any?

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
      "trainee_department" => "Trainee Department",
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
      "training_register_upload" => "Training Register Upload",
      "training_photo_upload_with_geo_tag" => "Training Photo Upload with Geo Tag"
    }

    errors = missing_required_data_errors(data, required_fields)
    selected_farmer_ids = Array(data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?).uniq
    farmer_count = whole_number_value(data["farmer_count"].presence || "0")
    male_count = whole_number_value(data["male_count"])
    female_count = whole_number_value(data["female_count"])
    total_farmer_count = whole_number_value(data["total_farmer_count"].presence || training_total_farmer_count(data).to_s)

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
    unless new_farmer_target
      errors << "Farmer Count required hai." if data["farmer_count"].blank?
      errors << "Mapped Farmers select karein." if selected_farmer_ids.blank?
      errors << "Farmer Count valid whole number hona chahiye." if farmer_count.nil?
      errors << "Farmer Count selected farmers ke count ke equal hona chahiye." if farmer_count && selected_farmer_ids.any? && farmer_count != selected_farmer_ids.size
      errors << "Farmer Count Target se jyada nahi ho sakta." if target && farmer_count && farmer_count > target
    end

    errors << "Mapped Other activity target select karein." if target_mapping.blank?
    errors << "Contact Number valid 10 digit hona chahiye." if data["contact_number"].present? && data["contact_number"].to_s.gsub(/\D/, "").length != 10
    errors
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
    @training_target_mappings = training_target_scope
      .order(:ics_name, :ics_id, :village_name, :village_id, :id)
      .filter_map do |target|
        activity_setting = activity_setting_for(target, activity_settings, sub_activity_settings)
        next if activity_setting.blank? || !training_main_activity_type?(activity_setting[:main_activity_type])

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

  def seed_distribution_target_mappings
    return @seed_distribution_target_mappings if defined?(@seed_distribution_target_mappings)
    return @seed_distribution_target_mappings = [] unless model_ready?(:TargetMapping)

    activity_settings = main_activity_settings
    sub_activity_settings = sub_activity_settings_for(activity_settings)

    @seed_distribution_target_mappings = training_target_scope
      .order(:ics_name, :ics_id, :village_name, :village_id, :id)
      .filter_map do |target|
        activity_setting = activity_setting_for(target, activity_settings, sub_activity_settings)
        next unless activity_setting.present? && !training_main_activity_type?(activity_setting[:main_activity_type])

        farmer_ids = target_farmer_ids(target)
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
          completed_farmer_ids: other_target_completed_farmer_ids_for(target.id),
          farmers: training_farmers_for_ids(farmer_ids)
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

    {
      jeevika_jankar_id: vrp&.id&.to_s,
      jeevika_jankar_name: vrp&.name.presence || current_app_user["name"].to_s,
      contact_number: (vrp&.mobile_no.presence || current_app_user["mobile_no"]).to_s.gsub(/\D/, "").last(10),
      department: vrp&.fcoc.presence || current_app_user["fcoc"].presence || current_app_user["fcoc_name"].to_s,
      trainer_name: vrp&.name.presence || current_app_user["name"].to_s,
      trainer_contact: (vrp&.mobile_no.presence || current_app_user["mobile_no"]).to_s.gsub(/\D/, "").last(10)
    }
  end

  def training_target_match(data)
    selected_month = normalize_text(data["month"])
    selected_ics = normalize_text(data["ics_block"].presence || data["ics"])
    selected_village = normalize_text(data["gram_name"].presence || data["village"])
    selected_main_activity = normalize_text(data["main_activity"].presence || data["training_topic"])
    selected_sub_activity = normalize_text(data["sub_activity"].presence || data["training_subject"])
    selected_main_activity_type = normalize_text(data["main_activity_type"])

    training_target_mappings.find do |mapping|
      normalize_text(mapping[:month]) == selected_month &&
        (selected_main_activity_type.blank? || normalize_text(mapping[:main_activity_type]) == selected_main_activity_type) &&
        normalize_text(mapping[:ics]) == selected_ics &&
        normalize_text(mapping[:village]) == selected_village &&
        normalize_text(mapping[:main_activity]) == selected_main_activity &&
        normalize_text(mapping[:sub_activity]) == selected_sub_activity
    end
  end

  def seed_distribution_target_match(data)
    selected_vrp = normalize_text(data["jeevika_jankar_id"].presence || data["jeevika_jankar_name"])
    selected_month = normalize_text(data["month"])
    selected_ics = normalize_text(data["ics"])
    selected_village = normalize_text(data["village"])
    selected_topic = normalize_text(data["training_topic"].presence || data["main_activity"])
    selected_subject = normalize_text(data["training_subject"].presence || data["sub_activity"])
    selected_main_activity_type = normalize_text(data["main_activity_type"])

    seed_distribution_target_mappings.find do |mapping|
      [mapping[:vrp_id], mapping[:jeevika_jankar_name]].any? { |value| normalize_text(value) == selected_vrp } &&
        (selected_main_activity_type.blank? || normalize_text(mapping[:main_activity_type]) == selected_main_activity_type) &&
        normalize_text(mapping[:month]) == selected_month &&
        normalize_text(mapping[:ics]) == selected_ics &&
        normalize_text(mapping[:village]) == selected_village &&
        normalize_text(mapping[:training_topic]) == selected_topic &&
        normalize_text(mapping[:training_subject]) == selected_subject
    end
  end

  def training_target_scope
    scope = TargetMapping.all
    scope = scope.where(vrp_id: current_vrp_record.id) if vrp_login_user? && current_vrp_record.present?
    scope = scope.where(vrp_id: cluster_visible_vrp_ids) if mapped_vrp_scope_active?
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

  def training_form_activity_scope_present?(data)
    data["month"].present? && data["gram_name"].present? && data["main_activity"].present? && data["sub_activity"].present?
  end

  def pending_training_farmer_ids_for(data)
    return nil unless model_ready?(:TargetMapping)

    selected_month = normalize_text(data["month"])
    selected_ics = normalize_text(data["ics_block"])
    selected_village = normalize_text(data["gram_name"])
    selected_main_activity_type = normalize_text(data["main_activity_type"])
    selected_main_activity = normalize_text(data["main_activity"])
    selected_sub_activity = normalize_text(data["sub_activity"])
    activity_settings = main_activity_settings

    training_target_scope.each_with_object([]) do |target, ids|
      activity_setting = activity_settings[normalize_text(target.main_activity_name)]
      next if activity_setting.blank? || !training_main_activity_type?(activity_setting[:main_activity_type])

      target_main_activity_type = normalize_text(activity_setting[:main_activity_type].presence || "Training")
      next if normalize_text(target.month_name) != selected_month
      next if selected_ics.present? && normalize_text(target.ics_name.presence || target.ics_id) != selected_ics
      next if normalize_text(target.village_name.presence || target.village_id) != selected_village
      next if selected_main_activity_type.present? && target_main_activity_type != selected_main_activity_type
      next if normalize_text(target.main_activity_name) != selected_main_activity
      next if normalize_text(target.activity_name) != selected_sub_activity

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
    Array(training_completion_index[key]) & farmer_ids
  end

  def training_completion_index
    return @training_completion_index if defined?(@training_completion_index)

    @training_completion_index = Hash.new { |hash, key| hash[key] = [] }
    return @training_completion_index unless model_ready?(:ModuleRecord)

    ModuleRecord.where(module_slug: "training-form").order(created_at: :desc).select { |record| active_module_record?(record) }.each do |record|
      next if @exclude_record_id.present? && record.id.to_s == @exclude_record_id.to_s

      summary = {
        month: record.data["month"],
        training_topic: record.data["main_activity"].presence || record.data["training_topic"],
        training_subject: record.data["sub_activity"].presence || record.data["training_subject"]
      }
      key = training_activity_key(summary[:month], summary[:training_topic], summary[:training_subject])
      next if key.all?(&:blank?)

      @training_completion_index[key] |= Array(record.data["selected_farmer_ids"]).map(&:to_s).reject(&:blank?)
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

    Afl.where(id: farmer_ids).order(:farmer_name, :id).map do |farmer|
      {
        id: farmer.id.to_s,
        farmer_name: farmer.farmer_name.presence || "Farmer ##{farmer.id}",
        father_name: farmer.father_name.to_s,
        tracenet_no: farmer.tracenet_no.to_s,
        mobile_no: farmer.mobile_no.to_s,
        khasara_no: farmer.khasara_no.to_s
      }
    end
  end

  def training_target_farmer_ids(target)
    saved_ids = Array(target.afl_ids).map(&:to_s).reject(&:blank?).uniq
    return saved_ids if saved_ids.any?

    mapped_ids = mapped_training_farmer_ids(target)
    return mapped_ids if mapped_ids.any?

    training_location_farmer_ids(target)
  end

  def mapped_training_farmer_ids(target)
    return [] unless model_ready?(:VrpIcsMapping)

    VrpIcsMapping.where(vrp_id: target.vrp_id).select do |mapping|
      training_location_matches?(mapping.fco_id, mapping.fco_name, target.fco_id, target.fco_name) &&
        training_location_matches?(mapping.ics_id, mapping.ics_name, target.ics_id, target.ics_name) &&
        training_location_matches?(mapping.village_id, mapping.village_name, target.village_id, target.village_name)
    end.flat_map { |mapping| Array(mapping.afl_ids).map(&:to_s) }.reject(&:blank?).uniq
  end

  def training_location_farmer_ids(target)
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
    uploads = Array(raw["training_photo_upload_with_geo_tag"] || raw[:training_photo_upload_with_geo_tag]).compact_blank
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

  def model_ready?(name)
    klass = name.to_s.safe_constantize
    klass.present? && (!klass.respond_to?(:table_exists?) || klass.table_exists?)
  end
end
