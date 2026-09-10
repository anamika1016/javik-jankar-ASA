require "net/http"
require "uri"

class TargetMappingsController < ApplicationController
  before_action :block_vrp_target_write, only: [:create, :destroy]

  TRAINING_TARGET_FIELDS = {
    "opg_training" => "OPG Training",
    "week_wise_opg" => "General Training/Meeting",
    "input_demo_inm" => "Input Demo INM",
    "input_demo_pm" => "Input Demo PM",
    "ffs" => "FFS"
  }.freeze

  def index
    @vrp_target_view = non_admin_vrp_login?
    @admin_mapping_actions = admin_login?
    @remove_mapping_actions = !admin_login? && !non_admin_vrp_login?
    @vrps = target_vrps
    @month_options = module_options("month-master", "month_name")
    @main_activity_options = module_options("add-activity-group", "main_activity_name", "activity_group_name")
    @main_activity_type_map = main_activity_type_map
    @target_sub_activity_map = target_sub_activity_map
    @block_fco_options = filtered_office_fco_options
    @block_options_by_fco = @block_fco_options.to_h do |option|
      fco_id, = parse_location_value(option[:value])
      [fco_id, office_block_options(option[:value])]
    end
    @target_mappings = dashboard_filtered_target_mappings(visible_target_mappings)
      .includes(:vrp, :vrp_ics_mapping).order(updated_at: :desc)
    # The table is deliberately rendered from row hashes (it also supports
    # summary rows).  Build the normal record rows here; previously this was
    # never assigned, so a successfully saved mapping always looked empty.
    @target_mapping_rows = target_mapping_rows(@target_mappings)
    @target_farmers_by_id = {}
    @edit_target = visible_target_mappings.find_by(id: params[:edit_id]) if params[:edit_id].present? && @admin_mapping_actions
    @edit_payload = edit_payload(@edit_target)
    @sub_activity_options = target_sub_activity_options(@edit_target&.main_activity_name)
  end

  def create
    if (opg_error = training_target_opg_error)
      redirect_to target_mappings_path, alert: opg_error
      return
    end
    if (plan_error = weekly_plan_error)
      redirect_to target_mappings_path, alert: plan_error
      return
    end

    if editable_target
      target_mapping = editable_target
      target_mapping.assign_attributes(single_target_mapping_attributes)
      apply_weekly_plan_target(target_mapping)
      target_mapping.vrp_ics_mapping_id = nil
      normalize_location_values(target_mapping)
      assign_afl_location_names(target_mapping)

      if target_vrp_allowed?(target_mapping) && assign_target_farmers(target_mapping) && target_mapping.save
        redirect_to target_mappings_path, notice: "Target mapping saved successfully."
      else
        redirect_to target_mappings_path, alert: target_mapping.errors.full_messages.to_sentence
      end
      return
    end

    mappings = build_target_mappings_for_selected_activities

    errors = mappings.flat_map do |target_mapping|
      valid_mapping = target_vrp_allowed?(target_mapping) && assign_target_farmers(target_mapping) && target_mapping.valid?
      valid_mapping ? [] : target_mapping.errors.full_messages
    end

    if mappings.any? && errors.blank?
      TargetMapping.transaction { mappings.each(&:save!) }
      redirect_to target_mappings_path, notice: "#{mappings.size} target mapping(s) saved successfully."
    else
      redirect_to target_mappings_path, alert: errors.presence&.to_sentence || training_target_mode_error_message
    end
  end

  def destroy
    visible_target_mappings.find(params[:id]).destroy
    redirect_to target_mappings_path, notice: admin_login? ? "Target mapping deleted successfully." : "Target mapping removed successfully."
  end

  def vrp_mappings
    block_wise = target_entry_mode_block_wise?
    village_value = target_village_param
    render json: {
      fco_options: block_wise ? office_fco_options : fco_options(params[:vrp_id]),
      block_options: block_wise ? office_block_options(params[:fco_id]) : [],
      ics_options: ics_options_for(params[:fco_id], params[:vrp_id]),
      village_options: block_wise ? office_village_options(params[:fco_id], params[:block_id]) : village_options_for(params[:fco_id], params[:ics_id], params[:vrp_id]),
      farmers: block_wise ? external_village_farmers_for(village_value) : target_farmers_for(
        vrp_id: params[:vrp_id],
        fco_id: params[:fco_id],
        ics_id: params[:ics_id],
        village_id: village_value,
        month_name: params[:month_name],
        main_activity_name: params[:main_activity_name],
        activity_name: params[:activity_name],
        edit_target: edit_target_for_json
      )
    }
  end

  def user_blocks
    render json: { options: user_block_options }
  end

  def village_farmers
    village_value = params[:village_id].presence || params[:village_ids]
    if params[:data_type].to_s == "short"
      count = external_village_farmer_count_for(village_value)
      if count.nil?
        render json: { error: "Farmer count unavailable" }, status: :service_unavailable
      else
        render json: { farmers: [], count: count }
      end
      return
    end

    farmers = external_village_farmers_for(village_value)
    render json: { farmers: farmers, count: farmers.size }
  end

  def saved_farmers
    ids = params[:target_mapping_ids].to_s.split(",").uniq
    targets = visible_target_mappings.where(id: ids)
    farmer_ids = targets.pluck(:afl_ids).flat_map { |values| normalized_afl_ids(values) }.uniq
    farmers = Afl.where(id: farmer_ids).order(:farmer_name, :id)
      .select(:id, :farmer_name, :father_name, :tracenet_no, :mobile_no, :village_name)
    render json: { farmers: farmers.as_json }
  end

  private

  def external_village_farmers_for(village_value)
    village_ids = parse_location_values(village_value).map(&:first).reject(&:blank?)
    return [] if village_ids.blank?

    village_ids.uniq.each_slice(6).flat_map do |batch|
      batch.map do |village_id|
        Thread.new do
          Rails.application.executor.wrap do
            Rails.cache.fetch(["asa-village-farmer-list", village_id], expires_in: 1.minute, skip_nil: true) do
              fetch_external_farmers(data_type: "detail", type: "village", id_key: "village_id", id: village_id)
            end
          end
        end
      end.then do |threads|
        ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
          threads.flat_map { |thread| thread.value || raise("Farmer list unavailable; please retry") }
        end
      end
    end
      .uniq { |farmer| farmer[:id].to_s }
      .sort_by { |farmer| [farmer[:farmer_name].to_s.downcase, farmer[:id].to_s] }
  end

  def external_village_farmer_count_for(village_value)
    village_ids = parse_location_values(village_value).map(&:first).reject(&:blank?).uniq
    # Bound concurrency so large village selections do not create one thread per village.
    counts = village_ids.each_slice(6).flat_map do |batch|
      batch.map do |village_id|
        Thread.new do
          Rails.application.executor.wrap do
            Rails.cache.fetch(["asa-village-farmer-count", village_id], expires_in: 1.minute, skip_nil: true) do
              fetch_external_farmer_count(village_id)
            end
          end
        end
      end.then do |threads|
        ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
      end
    end
    counts.any?(&:nil?) ? nil : counts.sum
  end

  def fetch_external_farmer_count(village_id)
    uri = URI("https://asa.ploughmanagro.com/api/farmers/get_farmers.json")
    uri.query = URI.encode_www_form(data_type: "short", type: "village", village_id: village_id)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 6) do |http|
      http.get(uri.request_uri)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    return nil if payload["success"] == false

    Integer(payload.fetch("count"))
  rescue StandardError => error
    Rails.logger.warn("Unable to load ASA farmer count for #{village_id}: #{error.class} - #{error.message}")
    nil
  end

  def fetch_external_farmers(data_type:, type:, id_key:, id:)
    return [] if id.blank?

    uri = URI("https://asa.ploughmanagro.com/api/farmers/get_farmers.json")
    uri.query = URI.encode_www_form(data_type: data_type, type: type, id_key => id)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 12) do |http|
      http.get(uri.request_uri)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    return nil if payload["success"] == false
    Array(payload["data"]).filter_map.with_index do |row, index|
      farmer = row["farmer"].is_a?(Hash) ? row["farmer"] : row
      address = row["address"].is_a?(Hash) ? row["address"] : {}
      grouping = row["grouping"].is_a?(Hash) ? row["grouping"] : {}
      farmer_id = farmer["farmer_unique_id"].presence || farmer["id"].presence || "#{type}-#{id}-#{index + 1}"
      farmer_name = farmer["farmer_name"].to_s.strip
      next if farmer_name.blank?

      {
        id: farmer_id.to_s,
        farmer_name: farmer_name,
        father_name: farmer["father_husband_name"].presence || farmer["father_name"].presence || "-",
        tracenet_no: farmer["tracenet_id"].presence || farmer["tracenet_no"].presence || "-",
        mobile_no: farmer["mobile_no"].presence || "-",
        khasara_no: Array(row["lands"]).filter_map { |land| land["khasra_no"].presence || land["plot_no"].presence }.join(", ").presence || "-",
        village_name: address["village"].presence || grouping["village"].presence || "-",
        selected: false
      }
    end
  rescue StandardError => error
    Rails.logger.warn("Unable to load ASA #{type} farmers for #{id}: #{error.class} - #{error.message}")
    nil
  end

  def user_block_options
    uri = URI("http://144.76.19.201:3003/api/get_user_list")
    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 8) do |http|
      http.get(uri.request_uri)
    end
    return [] unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    Array(payload["result"]).flat_map { |user| Array(user["working_zones"]) }.filter_map do |zone|
      block_id = zone["block_id"].to_s.strip
      block_name = zone["block"].to_s.strip
      next if block_id.blank? || block_name.blank?

      { value: [block_id, block_name].join("||"), label: block_name }
    end.uniq { |option| [option[:value], option[:label].downcase] }.sort_by { |option| option[:label].downcase }
  rescue JSON::ParserError, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout
    []
  end

  def block_vrp_target_write
    return unless non_admin_vrp_login?

    redirect_to target_mappings_path, alert: "VRP target records are view only for VRP login."
  end

  def target_mapping_params
    params.require(:target_mapping).permit(
      :vrp_id,
      :fco_id,
      :ics_id,
      :village_id,
      :month_name,
      :completion_date,
      :main_activity_name,
      :activity_name,
      :target_quantity,
      :target_entry_mode,
      :target_type,
      :new_farmer_target_quantity,
      main_activity_names: [],
      activity_names: [],
      afl_ids: [],
      training_targets: TRAINING_TARGET_FIELDS.keys,
      weekly_plan: [
        :main_activity,
        :sub_activity,
        :monthly,
        :week_1,
        :week_2,
        :week_3,
        :week_4,
        { afl_ids: [] }
      ]
    )
  end

  def single_target_mapping_attributes
    attrs = target_mapping_params.except(
      :main_activity_names,
      :activity_names,
      :afl_ids,
      :target_entry_mode,
      :target_type,
      :new_farmer_target_quantity,
      :training_targets,
      :weekly_plan
    )
    attrs[:main_activity_name] = target_activity_values(target_mapping_params[:main_activity_names]).first || attrs[:main_activity_name]
    attrs[:activity_name] = target_activity_values(target_mapping_params[:activity_names]).first || attrs[:activity_name]
    attrs[:target_quantity] = new_farmer_target_quantity if new_farmer_target_mode?
    attrs.merge!(training_target_attributes)
    attrs
  end

  def build_target_mappings_for_selected_activities
    target_activity_combinations.map do |main_activity, sub_activity|
      plan = weekly_plan_for(main_activity, sub_activity)
      target_mapping = TargetMapping.new(single_target_mapping_attributes.merge(
        main_activity_name: main_activity,
        activity_name: sub_activity,
        target_quantity: plan&.fetch("monthly", nil).presence || single_target_mapping_attributes[:target_quantity]
      ).merge(weekly_target_attributes(plan)))
      target_mapping.vrp_ics_mapping_id = nil
      normalize_location_values(target_mapping)
      assign_afl_location_names(target_mapping)
      assign_creator(target_mapping)
      target_mapping
    end
  end

  def build_target_mappings_for_training_targets
    selected_training_main_activity_names.product(selected_training_targets).map do |main_activity, (activity_name, quantity)|
      target_mapping = TargetMapping.new(single_target_mapping_attributes.merge(
        main_activity_name: main_activity,
        activity_name: activity_name,
        target_quantity: quantity
      ))
      target_mapping.vrp_ics_mapping_id = nil
      normalize_location_values(target_mapping)
      assign_afl_location_names(target_mapping)
      assign_creator(target_mapping)
      target_mapping
    end
  end

  def selected_training_targets
    raw = target_mapping_params[:training_targets]
    return [] unless raw.respond_to?(:to_h)

    raw.to_h.filter_map do |key, value|
      activity_name = TRAINING_TARGET_FIELDS[key.to_s]
      next if activity_name.blank?

      quantity = value.to_s.strip
      next if quantity.blank?
      # Skip zero-value entries — entering 0 means "not applicable" for
      # that training type; no mapping row should be created.
      next if quantity == "0" || quantity == "0.0"

      [activity_name, quantity]
    end
  end

  def training_target_attributes
    submitted_targets = target_mapping_params[:training_targets]

    TRAINING_TARGET_FIELDS.keys.index_with do |key|
      submitted_targets.respond_to?(:[]) ? submitted_targets[key].to_s.strip.presence : nil
    end.transform_keys { |key| "#{key}_target" }
  end

  def weekly_plan_rows
    raw = target_mapping_params[:weekly_plan]
    rows = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.values : Array(raw)
    fallback_main_activity = selected_main_activity_names.join(", ")
    fallback_sub_activity = selected_sub_activity_names.join(", ")

    rows.filter_map do |row|
      values = row.respond_to?(:to_h) ? row.to_h.stringify_keys : {}
      next if values["main_activity"].blank?

      values["main_activity"] = fallback_main_activity if common_activity_token?(values["main_activity"]) && fallback_main_activity.present?
      values["sub_activity"] = fallback_sub_activity if common_activity_token?(values["sub_activity"]) && fallback_sub_activity.present?
      values
    end
  end

  def weekly_plan_for(main_activity, sub_activity)
    exact_plan = weekly_plan_rows.find do |row|
      row_main_activities = target_activity_values(row["main_activity"])
      row_sub_activities = target_activity_values(row["sub_activity"])
      main_match = row_main_activities.any? { |value| value.casecmp(main_activity.to_s.strip).zero? }
      sub_match = row_sub_activities.blank? || row_sub_activities.any? { |value| value.casecmp(sub_activity.to_s.strip).zero? }

      main_match && sub_match
    end
    return exact_plan if exact_plan

    weekly_plan_rows.find do |row|
      common_activity_token?(row["main_activity"]) ||
        row["main_activity"].to_s.include?(",") ||
        row["sub_activity"].to_s.include?(",")
    end
  end

  def apply_weekly_plan_target(target_mapping)
    training_target = selected_training_targets.find do |activity_name, _quantity|
      activity_name.to_s.casecmp(target_mapping.activity_name.to_s).zero?
    end
    if training_target
      target_mapping.target_quantity = training_target.last
      return
    end

    plan = weekly_plan_for(target_mapping.main_activity_name, target_mapping.activity_name)
    target_mapping.target_quantity = plan["monthly"] if plan&.dig("monthly").present?
    target_mapping.assign_attributes(weekly_target_attributes(plan)) if plan
  end

  def weekly_target_attributes(plan)
    return {} unless plan

    {
      week_1_target: integer_plan_value(plan["week_1"]),
      week_2_target: integer_plan_value(plan["week_2"]),
      week_3_target: integer_plan_value(plan["week_3"]),
      week_4_target: integer_plan_value(plan["week_4"])
    }
  end

  OPG_BREAKDOWN_KEYS = %w[week_wise_opg input_demo_inm input_demo_pm ffs].freeze

  def weekly_plan_error
    # New Farmer Target is not activity based.  It deliberately has no weekly
    # plan, Main Activity, or Sub Activity.
    return nil if new_farmer_target_mode?

    weekly_plan_rows.each do |row|
      monthly = integer_plan_value(row["monthly"])
      weeks = %w[week_1 week_2 week_3 week_4].map { |field| integer_plan_value(row[field]) }
      activity = [row["main_activity"], row["sub_activity"]].compact_blank.join(" - ")

      return "#{activity}: Monthly target must be greater than 0." unless monthly&.positive?
      return "#{activity}: Week targets must be whole numbers." if weeks.any?(&:nil?)
      return "#{activity}: Week 1 to Week 4 total must equal Monthly target (#{monthly})." unless weeks.sum == monthly
    end

    nil
  end

  def integer_plan_value(value)
    number = BigDecimal(value.to_s)
    return unless number >= 0 && number == number.to_i

    number.to_i
  rescue ArgumentError
    nil
  end

  def selected_main_activity_names
    target_activity_values(
      target_mapping_params[:main_activity_names].presence || target_mapping_params[:main_activity_name]
    )
  end

  def selected_sub_activity_names
    target_activity_values(
      target_mapping_params[:activity_names].presence || target_mapping_params[:activity_name]
    )
  end

  def common_activity_token?(value)
    value.to_s.strip.gsub("_", "").casecmp("common").zero?
  end

  def training_target_mode?
    selected_training_main_activity_names.any?
  end

  def selected_training_main_activity_names
    selected_main_activity_names.select { |name| training_main_activity_type?(main_activity_type_for(name)) }
  end

  def training_box_activity?(activity_name)
    TRAINING_TARGET_FIELDS.value?(activity_name.to_s)
  end

  def training_main_activity_type?(value)
    value.to_s.strip.casecmp("Training").zero?
  end

  def training_target_mode_error_message
    if training_target_mode?
      "Please enter at least one Training target (OPG Training, General Training/Meeting, Input Demo INM, Input Demo PM, or FFS)."
    else
      "Please select at least one Main Activity and Sub Activity."
    end
  end

  def target_activity_combinations
    if new_farmer_target_mode?
      selected = selected_target_activity_combinations
      return selected if selected.any?
      return [] if selected_main_activity_names.any? || selected_sub_activity_names.any?

      return [["New Farmer Target", "New Farmer Target"]]
    end

    selected_combinations = selected_target_activity_combinations
    return selected_combinations if selected_combinations.any?

    planned_combinations = weekly_plan_rows.map do |row|
      [row["main_activity"].to_s.strip, row["sub_activity"].to_s.strip.presence || row["main_activity"].to_s.strip]
    end.reject { |main_activity, sub_activity| main_activity.blank? || sub_activity.blank? }.uniq
    return planned_combinations if planned_combinations.any?

    []
  end

  def selected_target_activity_combinations
    main_activities = target_activity_values(target_mapping_params[:main_activity_names].presence || target_mapping_params[:main_activity_name])
    sub_activities = selected_sub_activity_names
    return [] if main_activities.blank? || sub_activities.blank?

    mapped_pairs = target_sub_activity_map.map do |row|
      [row[:main_activity].to_s.strip, row[:sub_activity].to_s.strip]
    end

    main_activities.product(sub_activities).select do |main_activity, sub_activity|
      mapped_pairs.blank? || mapped_pairs.any? do |mapped_main, mapped_sub|
        mapped_main.casecmp(main_activity).zero? && mapped_sub.casecmp(sub_activity).zero?
      end
    end.uniq
  end

  def target_activity_values(value)
    case value
    when Array
      value.flat_map { |item| target_activity_values(item) }
    when String
      stripped = value.strip
      return [] if stripped.blank?

      if stripped.start_with?("[")
        parsed = JSON.parse(stripped)
        return target_activity_values(parsed)
      end

      [stripped]
    else
      Array(value).flat_map { |item| target_activity_values(item) }
    end.map(&:to_s).map(&:strip).reject { |v| v.blank? || v == "__common__" }.uniq
  rescue JSON::ParserError
    [value.to_s.strip].reject { |v| v.blank? || v == "__common__" }
  end

  def target_village_param
    params[:village_ids].presence || params[:village_id]
  end

  def editable_target
    return if params.dig(:target_mapping, :id).blank?

    visible_target_mappings.find(params.dig(:target_mapping, :id))
  end

  def target_vrps
    return Vrp.where(id: current_app_user["id"]).order(:name, :id) if non_admin_vrp_login?

    scope = Vrp.all
    scope = scope.where(status: 55) if Vrp.column_names.include?("status")
    scope = scope.where(is_active: true) if Vrp.column_names.include?("is_active")
    scope = scope.merge(own_registered_vrps) unless admin_login?
    scope.order(:name, :id)
  end

  def target_vrp_allowed?(target_mapping)
    return true if target_vrps.where(id: target_mapping.vrp_id).exists?

    target_mapping.errors.add(:vrp_id, "is not registered by you")
    false
  end

  def own_registered_vrps
    ids = current_app_user_ids
    return Vrp.none if ids.blank?

    scope = Vrp.none
    if ids.any?
      scope = scope.or(Vrp.where(created_by_id: ids))
      scope = scope.or(Vrp.where(user_id: ids)) if Vrp.column_names.include?("user_id")
    end

    scope
  end

  def assign_afl_location_names(target_mapping)
    afl = afl_scope_for_location(
      target_mapping.fco_id,
      target_mapping.ics_id,
      target_mapping.village_id,
      target_mapping.fco_name,
      target_mapping.ics_name,
      target_mapping.village_name
    ).first

    target_mapping.fco_name = target_mapping.fco_name.presence || afl&.fco
    target_mapping.ics_name = target_mapping.ics_name.presence || afl&.ics_name
    target_mapping.village_name = target_mapping.village_name.presence || afl&.village_name
  end

  def assign_target_farmers(target_mapping)
    return assign_external_target_farmers(target_mapping) if target_entry_mode_block_wise?

    mapped_farmer_ids = afl_ids_for_location(
      target_mapping.fco_id,
      target_mapping.ics_id,
      target_mapping.village_id,
      target_mapping.fco_name,
      target_mapping.ics_name,
      target_mapping.village_name,
      vrp_id: target_mapping.vrp_id
    )
    plan = weekly_plan_for(target_mapping.main_activity_name, target_mapping.activity_name)
    selected_ids = normalized_afl_ids(plan ? plan["afl_ids"] : target_mapping_params[:afl_ids])
    selected_ids = submitted_farmer_ids if selected_ids.blank? && submitted_farmer_ids.present?
    if selected_ids.present? && target_mapping.target_quantity.to_i <= 0
      target_mapping.target_quantity = selected_ids.size
    end
    target_count = target_farmer_count(target_mapping)
    return false unless target_count

    target_mapping.afl_ids = selected_ids if plan
    if training_box_activity?(target_mapping.activity_name) || new_farmer_target_mode? || village_target_mode?
      if target_count <= 0
        target_mapping.errors.add(training_box_activity?(target_mapping.activity_name) ? :activity_name : :target_quantity, "target must be greater than 0")
        return false
      end

      target_mapping.afl_ids = []
      target_mapping.farmer_count = 0
      return true
    end

    if selected_ids.blank?
      target_mapping.errors.add(:afl_ids, "select at least one farmer")
      return false
    end

    if target_count != selected_ids.size
      target_mapping.errors.add(:target_quantity, "must match selected farmers count")
      return false
    end

    if selected_ids.size > mapped_farmer_ids.size && mapped_farmer_ids.any?
      target_mapping.errors.add(:target_quantity, "cannot be greater than registered farmers")
      return false
    end

    invalid_ids = selected_ids - mapped_farmer_ids
    if invalid_ids.any?
      target_mapping.errors.add(:afl_ids, "include farmers outside selected villages")
      return false
    end

    already_selected_ids = normalized_afl_ids(target_mapping.afl_ids)
    blocked_ids = (selected_ids - already_selected_ids) & assigned_farmer_ids_for(target_mapping)
    if blocked_ids.any?
      target_mapping.errors.add(:afl_ids, "#{blocked_ids.size} farmer already assigned for this activity")
      return false
    end

    target_mapping.afl_ids = selected_ids
    target_mapping.farmer_count = selected_ids.size
    true
  end

  def assign_external_target_farmers(target_mapping)
    plan = weekly_plan_for(target_mapping.main_activity_name, target_mapping.activity_name)
    selected_ids = normalized_afl_ids(plan ? plan["afl_ids"] : target_mapping_params[:afl_ids])
    selected_ids = submitted_farmer_ids if selected_ids.blank? && submitted_farmer_ids.present?
    if selected_ids.present? && target_mapping.target_quantity.to_i <= 0
      target_mapping.target_quantity = selected_ids.size
    end
    target_count = target_farmer_count(target_mapping)
    return false unless target_count

    target_mapping.afl_ids = selected_ids if plan
    if training_box_activity?(target_mapping.activity_name) || new_farmer_target_mode? || village_target_mode?
      if target_count <= 0
        target_mapping.errors.add(training_box_activity?(target_mapping.activity_name) ? :activity_name : :target_quantity, "target must be greater than 0")
        return false
      end

      target_mapping.afl_ids = []
      target_mapping.farmer_count = 0
      return true
    end

    if selected_ids.blank?
      target_mapping.errors.add(:afl_ids, "select at least one farmer")
      return false
    end

    if target_count != selected_ids.size
      target_mapping.errors.add(:target_quantity, "must match selected farmers count")
      return false
    end

    target_mapping.afl_ids = selected_ids
    target_mapping.farmer_count = selected_ids.size
    true
  end

  def target_farmer_count(target_mapping)
    quantity = BigDecimal(target_mapping.target_quantity.to_s)
    if quantity < 0 || quantity != quantity.to_i
      target_mapping.errors.add(:target_quantity, "must be a whole number of farmers")
      return nil
    end

    quantity.to_i
  rescue ArgumentError
    target_mapping.errors.add(:target_quantity, "is not a number")
    nil
  end

  def new_farmer_target_mode?
    new_farmer_target_quantity.present? && submitted_farmer_ids.blank?
  end

  def village_target_mode?
    target_mapping_params[:target_type].to_s.strip.downcase == "village"
  end

  def submitted_farmer_ids
    direct_ids = normalized_afl_ids(target_mapping_params[:afl_ids])
    planned_ids = weekly_plan_rows.flat_map { |row| normalized_afl_ids(row["afl_ids"]) }
    (direct_ids + planned_ids).uniq
  end

  def new_farmer_target_quantity
    target_mapping_params[:new_farmer_target_quantity].to_s.strip
  end

  def target_farmers_for(vrp_id:, fco_id:, ics_id:, village_id:, month_name:, main_activity_name:, activity_name:, edit_target: nil)
    return [] if vrp_id.blank? || fco_id.blank? || ics_id.blank? || village_id.blank?
    return [] unless defined?(Afl) && Afl.table_exists?

    assigned_ids = assigned_farmer_ids_for_location(
      vrp_id: vrp_id,
      fco_id: fco_id,
      ics_id: ics_id,
      village_id: village_id,
      month_name: month_name,
      main_activity_name: main_activity_name,
      activity_name: activity_name,
      edit_target: edit_target
    )
    selected_ids = normalized_afl_ids(edit_target&.afl_ids)

    parsed_fco_id, parsed_fco_name = parse_location_value(fco_id)
    parsed_ics_id, parsed_ics_name = parse_location_value(ics_id)
    parsed_village_values = parse_location_values(village_id)
    return [] if parsed_village_values.blank?

    target_afl_scope_for_location(
      vrp_id,
      parsed_fco_id,
      parsed_ics_id,
      parsed_village_values.map(&:first),
      parsed_fco_name,
      parsed_ics_name,
      parsed_village_values.map(&:last)
    )
      .to_a
      .then do |afls|
        profiles_by_id = target_farmer_profiles_by_id(afls)

        afls.map do |afl|
          profile = profiles_by_id[afl.id.to_s] || {}
          {
            id: afl.id.to_s,
            farmer_name: profile[:farmer_name].presence || "Farmer ##{afl.id}",
            father_name: profile[:father_name].presence || "-",
            tracenet_no: profile[:tracenet_no].presence || "-",
            mobile_no: profile[:mobile_no].presence || "-",
            khasara_no: profile[:khasara_no].presence || "-",
            assigned_to_other: assigned_ids.include?(afl.id.to_s),
            selected: selected_ids.include?(afl.id.to_s)
          }
        end.sort_by { |row| [row[:farmer_name].to_s.downcase, row[:id].to_s] }
      end
  end

  def assigned_farmer_ids_for(target_mapping)
    assigned_farmer_ids_for_location(
      vrp_id: target_mapping.vrp_id,
      fco_id: encoded_location_value(target_mapping.fco_id, target_mapping.fco_name),
      ics_id: encoded_location_value(target_mapping.ics_id, target_mapping.ics_name),
      village_id: target_mapping.village_id,
      month_name: target_mapping.month_name,
      main_activity_name: target_mapping.main_activity_name,
      activity_name: target_mapping.activity_name,
      edit_target: target_mapping
    )
  end

  def assigned_farmer_ids_for_location(vrp_id:, fco_id:, ics_id:, village_id:, month_name:, main_activity_name: nil, activity_name: nil, edit_target: nil)
    main_activity_names = target_activity_values(main_activity_name)
    activity_names = target_activity_values(activity_name)
    return [] if month_name.blank? || main_activity_names.blank? || activity_names.blank?

    scope = TargetMapping.all
    scope = scope.where("LOWER(TRIM(month_name)) = ?", month_name.to_s.strip.downcase)
    scope = scope.where("LOWER(TRIM(main_activity_name)) IN (?)", main_activity_names.map { |value| value.to_s.strip.downcase })
    scope = scope.where("LOWER(TRIM(activity_name)) IN (?)", activity_names.map { |value| value.to_s.strip.downcase })
    scope = scope.where.not(id: edit_target.id) if edit_target&.persisted?

    scope.pluck(:afl_ids).flat_map { |ids| normalized_afl_ids(ids) }.uniq
  end

  def afl_ids_for_location(fco_id, ics_id, village_id, fco_name = nil, ics_name = nil, village_name = nil, vrp_id: nil)
    return [] unless defined?(Afl) && Afl.table_exists?

    mapped_ids = mapped_afl_ids_for_location(
      vrp_id: vrp_id,
      fco_id: fco_id,
      ics_id: ics_id,
      village_id: village_id,
      fco_name: fco_name,
      ics_name: ics_name,
      village_name: village_name
    )
    return mapped_ids if mapped_ids.any?

    afl_scope_for_location(fco_id, ics_id, village_id, fco_name, ics_name, village_name).pluck(:id).map(&:to_s).uniq
  end

  def fco_options(vrp_id = nil)
    unique_fco_options(afl_fco_options + saved_location_options(vrp_id, :fco_id, :fco_name))
  end

  # Block-wise targets are assigned to offices, rather than to an AFL FCO.
  def filtered_office_fco_options
    all_options = office_fco_options
    return all_options if admin_login?

    fco_id = user_mapped_office_fco_id
    return all_options if fco_id.nil?

    matched = all_options.select { |opt| parse_location_value(opt[:value]).first == fco_id }
    matched.any? ? matched : all_options
  end

  def user_mapped_office_fco_id
    items = office_list_items
    return nil if items.blank?

    fco_ids = Set.new
    fco_by_id = {}
    items.each do |o|
      next unless o.dig("office_name", "name").to_s.strip.casecmp("fco").zero?
      fco_ids << o["id"].to_s
      fco_by_id[o["id"].to_s] = o
    end

    keywords = [
      current_app_user["block"],
      current_app_user["district"],
      current_app_user["sub_office_name"]&.gsub(/\ATO\s*[-]\s*/i, ""),
      current_app_user["office_name"]&.gsub(/\AFCO[-\s]*C?\s*/i, "")
    ].map { |v| v.to_s.strip.downcase }.reject(&:blank?).uniq

    return nil if keywords.blank?

    items.each do |o|
      parent_id = o.dig("parent", "id").to_s
      next unless fco_ids.include?(parent_id)

      child_name = o["name"].to_s.strip.downcase
        .gsub(/[-\s]*(to|fpc|ics|fpo)\s*\z/i, "").strip
      keywords.each do |kw|
        return parent_id if child_name.present? && (child_name.include?(kw) || kw.include?(child_name))
      end
    end

    keywords.each do |kw|
      fco_by_id.each do |id, fco|
        fco_name = fco["name"].to_s.strip.downcase
          .gsub(/[-\s]*(papl|fco)\s*\z/i, "").strip
        return id if fco_name.present? && (fco_name.include?(kw) || kw.include?(fco_name))
      end
    end

    nil
  end

  def office_fco_options
    api_options = office_list_fco_options
    return api_options if api_options.any?

    office_mapping_fco_options
  end

  def office_list_fco_options
    office_list_items.filter_map do |office|
      category = office.dig("office_name", "name").to_s.strip
      next unless category.casecmp("fco").zero?

      office_name = office["name"].to_s.strip
      next if office_name.blank?

      option_hash(office["id"].presence || office_name, office_name)
    end.then { |options| unique_fco_options(options).sort_by { |option| option[:label].to_s.downcase } }
  end

  def office_block_options(fco_value)
    fco_id, fco_name = parse_location_value(fco_value)
    return [] if fco_id.blank? && fco_name.blank?

    office_list_items
      .select do |office|
        office_id = office["id"].to_s.strip
        office_name = office["name"].to_s.strip
        parent_id = office.dig("parent", "id").to_s.strip
        parent_name = office.dig("parent", "name").to_s.strip
        selected_name = fco_name.presence || fco_id

        # FCO records normally have their blocks on the child FPC/ICS offices,
        # whose parent is the selected FCO (for example, Betul-FCO -> Athner).
        office_id == fco_id ||
          office_name.casecmp?(selected_name) ||
          parent_id == fco_id ||
          parent_name.casecmp?(selected_name)
      end
      .flat_map { |office| Array(office["territory_zones"]) }
      .flat_map { |zone| Array(zone["block"]) }
      .filter_map do |block|
        block_id = block["id"].presence || block["block_id"].presence
        block_name = office_location_name(block["name"]).presence || office_location_name(block["block_name"])
        next if block_name.blank?

        option_hash(block_id || block_name, block_name)
      end
      .then { |options| unique_location_options(options).sort_by { |option| option[:label].to_s.downcase } }
  end

  def office_village_options(fco_value, block_value)
    fco_id, fco_name = parse_location_value(fco_value)
    block_id, block_name = parse_location_value(block_value)
    return [] if fco_id.blank? || block_id.blank?

    offices = office_list_items
    office_ids = office_descendant_ids(offices, fco_id, fco_name)
    return [] if office_ids.blank?

    offices
      .select { |office| office_ids.include?(office["id"].to_s) }
      .flat_map { |office| Array(office["territory_zones"]) }
      .select do |zone|
        Array(zone["block"]).any? do |block|
          zone_block_id = block["id"].to_s
          zone_block_name = office_location_name(block["name"])
          zone_block_id == block_id || zone_block_name.to_s.casecmp?(block_name.presence || block_id)
        end
      end
      .flat_map { |zone| Array(zone["village"]) }
      .filter_map do |village|
        village_id = village["id"].presence || village["village_id"].presence
        village_name = office_location_name(village["name"]).presence || office_location_name(village["village_name"])
        next if village_name.blank?

        option_hash(village_id || village_name, village_name)
      end
      .then { |options| unique_location_options(options).sort_by { |option| option[:label].to_s.downcase } }
  end

  def office_descendant_ids(offices, fco_id, fco_name)
    selected_name = fco_name.presence || fco_id
    ids = offices.filter_map do |office|
      office_id = office["id"].to_s
      office_name = office["name"].to_s.strip
      office_id if office_id == fco_id || office_name.casecmp?(selected_name)
    end.uniq

    loop do
      child_ids = offices.filter_map do |office|
        office_id = office["id"].to_s
        office_id if office.dig("parent", "id").to_s.in?(ids) && !ids.include?(office_id)
      end
      break if child_ids.empty?

      ids.concat(child_ids)
    end
    ids
  end

  def office_list_items
    return @office_list_items if defined?(@office_list_items)

    @office_list_items = Rails.cache.fetch("office-list-api-items-v1", expires_in: 10.minutes) do
      office_list_api_urls.each do |url|
        items = fetch_office_list_items(url)
        break items if items.any?
      end || []
    end
  end

  def fetch_office_list_items(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 8) do |http|
      http.get(uri.request_uri)
    end
    return [] unless response.is_a?(Net::HTTPSuccess)

    Array(JSON.parse(response.body)["result"])
  rescue StandardError => error
    Rails.logger.warn("Unable to load Office List from #{url}: #{error.message}")
    []
  end

  def office_list_api_urls
    [
      "http://144.76.19.201:3003/api/get_office_detail_list",
      "https://asa.ploughmanagro.com/api/get_office_detail_list"
    ]
  end

  def office_location_name(value)
    value.is_a?(Hash) ? value["en"].presence || value["hn"].presence : value.to_s.strip
  end

  # Keep locally maintained Office Setup records as a fallback when the Office
  # List service is temporarily unavailable.
  def office_mapping_fco_options
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    ModuleRecord.where(module_slug: "office-mapping-add")
      .order(created_at: :desc)
      .select { |record| record.data["status"].blank? || record.data["status"].to_s.casecmp("active").zero? }
      .filter_map do |record|
        category = first_present_data(record, "office_name", "office_category", "category_name").to_s.strip
        next unless category.casecmp("fco").zero?

        office_name = first_present_data(record, "sub_office_name", "office_mapping", "office").to_s.strip
        next if office_name.blank?

        option_hash(office_name, office_name)
      end
      .then { |options| unique_fco_options(options).sort_by { |option| option[:label].to_s.downcase } }
  end

  def target_entry_mode_block_wise?
    params[:target_entry_mode].to_s == "block_wise" ||
      (params[:target_mapping].respond_to?(:[]) && params[:target_mapping][:target_entry_mode].to_s == "block_wise")
  end

  def ics_options_for(fco_value, vrp_id = nil)
    return [] if fco_value.blank?

    mapping_scope = filter_mapping_location(mapped_location_scope(vrp_id), :fco_id, :fco_name, fco_value)
    target_scope = filter_mapping_location(target_location_scope(vrp_id), :fco_id, :fco_name, fco_value)
    saved_options = saved_location_options(vrp_id, :ics_id, :ics_name, mapping_scope, target_scope)

    unique_location_options(afl_ics_options_for(fco_value) + saved_options)
  end

  def village_options_for(fco_value, ics_value, vrp_id = nil)
    return [] if fco_value.blank? || ics_value.blank?

    mapping_scope = filter_mapping_location(mapped_location_scope(vrp_id), :fco_id, :fco_name, fco_value)
    mapping_scope = filter_mapping_location(mapping_scope, :ics_id, :ics_name, ics_value)
    target_scope = filter_mapping_location(target_location_scope(vrp_id), :fco_id, :fco_name, fco_value)
    target_scope = filter_mapping_location(target_scope, :ics_id, :ics_name, ics_value)
    saved_options = saved_location_options(vrp_id, :village_id, :village_name, mapping_scope, target_scope)

    unique_location_options(afl_village_options_for(fco_value, ics_value) + saved_options)
  end

  def afl_fco_options
    return [] unless defined?(Afl) && Afl.table_exists?

    Afl
      .where.not(fco_id: [nil, ""])
      .or(Afl.where.not(fco: [nil, ""]))
      .select(:fco_id, :fco)
      .distinct
      .order(:fco, :fco_id)
      .map { |afl| option_hash(afl.fco_id.presence || afl.fco, afl.fco) }
  end

  def afl_ics_options_for(fco_value)
    return [] if fco_value.blank? || !defined?(Afl) || !Afl.table_exists?

    fco_id, fco_name = parse_location_value(fco_value)
    scope = filter_afl_location(Afl.all, :fco_id, :fco, fco_id, fco_name)
    scope
      .where.not(ics_id: [nil, ""])
      .select(:ics_id, :ics_name)
      .distinct
      .order(:ics_name, :ics_id)
      .map { |afl| option_hash(afl.ics_id, afl.ics_name) }
  end

  def afl_village_options_for(fco_value, ics_value)
    return [] if fco_value.blank? || ics_value.blank? || !defined?(Afl) || !Afl.table_exists?

    fco_id, fco_name = parse_location_value(fco_value)
    ics_id, ics_name = parse_location_value(ics_value)
    scope = filter_afl_location(Afl.all, :fco_id, :fco, fco_id, fco_name)
    scope = filter_afl_location(scope, :ics_id, :ics_name, ics_id, ics_name)
    scope
      .where.not(village_id: [nil, ""])
      .select(:village_id, :village_name)
      .distinct
      .order(:village_name, :village_id)
      .map { |afl| option_hash(afl.village_id, afl.village_name) }
  end

  def mapped_location_scope(vrp_id = nil)
    scope = visible_vrp_ics_mappings
    scope = scope.where(vrp_id: vrp_id) if vrp_id.present?
    scope
  end

  def target_location_scope(vrp_id = nil)
    scope = visible_target_mappings
    scope = scope.where(vrp_id: vrp_id) if vrp_id.present?
    scope
  end

  def saved_location_options(vrp_id, id_column, name_column, mapping_scope = nil, target_scope = nil)
    mapping_scope ||= mapped_location_scope(vrp_id)
    target_scope ||= target_location_scope(vrp_id)

    unique_location_options(
      mapping_location_options(mapping_scope, id_column, name_column) +
      target_location_options(target_scope, id_column, name_column)
    )
  end

  def unique_location_options(options)
    Array(options).uniq { |option| [option[:value].to_s, option[:label].to_s] }
  end

  def unique_fco_options(options)
    Array(options).each_with_object({}) do |option, unique|
      fco_id, fco_name = parse_location_value(option[:value])
      fco_id = fco_id.to_s.strip
      fco_name = fco_name.to_s.strip
      fco_name = option[:label].to_s.strip if fco_name.blank?
      fco_name = fco_name.sub(/\s*-\s*#{Regexp.escape(fco_id)}\s*\z/i, "").strip if fco_id.present?

      next if fco_id.blank? || fco_name.blank?
      next if [fco_id, fco_name].any? { |value| value.casecmp("null").zero? }

      normalized = option_hash(fco_id, fco_name)
      key = fco_name.downcase
      current = unique[key]
      current_id, current_name = parse_location_value(current&.dig(:value))
      current_has_code = current.present? && current_id.present? && !current_id.casecmp(current_name.to_s).zero?
      candidate_has_code = !fco_id.casecmp(fco_name).zero?

      unique[key] = normalized if current.blank? || (!current_has_code && candidate_has_code)
    end.values
  end

  def mapping_location_options(scope, id_column, name_column)
    location_options(scope, id_column, name_column)
  end

  def target_location_options(scope, id_column, name_column)
    location_options(scope, id_column, name_column)
  end

  def location_options(scope, id_column, name_column)
    return [] unless scope

    scope
      .where.not(id_column => [nil, ""])
      .reorder(name_column => :asc, id_column => :asc)
      .pluck(id_column, name_column)
      .uniq
      .map { |value, label| option_hash(value, label) }
  end

  def filter_mapping_location(scope, id_column, name_column, location_value)
    id, label = parse_location_value(location_value)
    return scope.none if id.blank?

    id_scope = scope.where(id_column => id)
    return id_scope if label.blank?

    label_scope = id_scope.where(name_column => label)
    label_scope.exists? ? label_scope : id_scope
  end

  def mapped_afl_ids_for_location(vrp_id:, fco_id:, ics_id:, village_id:, fco_name: nil, ics_name: nil, village_name: nil)
    return [] unless defined?(VrpIcsMapping) && VrpIcsMapping.table_exists?

    village_values = parse_location_values(village_id)
    village_ids = village_values.map(&:first).reject(&:blank?).uniq
    village_names = Array(village_name).flat_map { |value| label_value_list(value) }.presence ||
      village_values.map(&:last).reject(&:blank?).uniq
    return [] if fco_id.blank? || ics_id.blank? || village_ids.blank?

    scope = mapped_location_scope(vrp_id)
    scope = filter_mapping_location(scope, :fco_id, :fco_name, encoded_location_value(fco_id, fco_name))
    scope = filter_mapping_location(scope, :ics_id, :ics_name, encoded_location_value(ics_id, ics_name))
    scope.to_a
      .select do |mapping|
        mapped_village_ids = parse_location_values(mapping.village_id).map(&:first)
        mapped_village_names = label_value_list(mapping.village_name)
        (mapped_village_ids & village_ids).any? ||
          (village_names.present? && (mapped_village_names & village_names).any?)
      end
      .flat_map { |mapping| normalized_afl_ids(mapping.afl_ids) }
      .uniq
  end

  def target_afl_scope_for_location(vrp_id, fco_id, ics_id, village_id, fco_name = nil, ics_name = nil, village_name = nil)
    mapped_ids = mapped_afl_ids_for_location(
      vrp_id: vrp_id,
      fco_id: fco_id,
      ics_id: ics_id,
      village_id: village_id,
      fco_name: fco_name,
      ics_name: ics_name,
      village_name: village_name
    )
    if mapped_ids.any?
      mapped_scope = Afl.where(id: mapped_ids)
      return mapped_scope if mapped_scope.exists?
    end

    afl_scope_for_location(fco_id, ics_id, village_id, fco_name, ics_name, village_name)
  end

  def option_hash(value, label)
    text = label.present? && label.to_s == value.to_s ? label.to_s : [label.presence, value].compact.join(" - ")
    { value: encoded_location_value(value, label), label: text.presence || value.to_s }
  end

  def target_farmer_profiles_by_id(afls)
    afls = Array(afls)
    ids = afls.map { |afl| afl.id.to_s }.reject(&:blank?).uniq
    return {} if ids.blank?

    afls_by_id = afls.index_by { |afl| afl.id.to_s }
    ids.each_with_object({}) do |id, memo|
      afl = afls_by_id[id]
      # AFL already contains the fields shown in Target Mapping.  Resolving
      # every selected farmer again through name-based Farmer Information and
      # Exit Declaration searches created massive IN queries and delayed a
      # target submit by several seconds.  Use this one preloaded AFL batch.
      memo[id] = {
        id: id,
        farmer_name: target_farmer_text_value(afl&.farmer_name).presence || "Farmer ##{id}",
        father_name: target_farmer_text_value(afl&.father_name),
        tracenet_no: target_farmer_text_value(afl&.tracenet_no),
        mobile_no: target_farmer_text_value(afl&.mobile_no),
        khasara_no: target_farmer_text_value(afl&.khasara_no),
        village_name: target_farmer_text_value(afl&.village_name)
      }
    end
  end

  def target_farmer_information_records(afls)
    return [] unless defined?(FarmerFarmInformation) && FarmerFarmInformation.table_exists?

    afls = Array(afls)
    ids = afls.map { |afl| afl.id.to_s }.reject(&:blank?).uniq
    tracenets = afls.map { |afl| target_farmer_text_value(afl&.tracenet_no) }.compact
    aadhars = afls.flat_map { |afl| [afl.aadhar, afl.qr_aadhar] }.map { |value| target_farmer_text_value(value) }.compact
    mobiles = afls.map { |afl| target_farmer_text_value(afl&.mobile_no) }.compact
    names = afls.map { |afl| target_farmer_text_value(afl&.farmer_name) }.compact
    declaration_ids = target_farmer_exit_declarations(afls).values.map { |declaration| declaration&.farmer_farm_information_id.to_s }.reject(&:blank?).uniq

    scope = FarmerFarmInformation.none
    scope = scope.or(FarmerFarmInformation.where(farm_id: ids)) if ids.any?
    scope = scope.or(FarmerFarmInformation.where(tracenet_no: tracenets)) if tracenets.any?
    scope = scope.or(FarmerFarmInformation.where(aadhar_number: aadhars)) if aadhars.any?
    scope = scope.or(FarmerFarmInformation.where(farmer_contact_no: mobiles)) if mobiles.any?
    scope = scope.or(FarmerFarmInformation.where(farmer_name: names)) if names.any?
    scope = scope.or(FarmerFarmInformation.where(id: declaration_ids)) if declaration_ids.any?

    scope.to_a.uniq { |farmer| farmer.id }
  end

  def target_farmer_exit_declarations(afls)
    return {} unless defined?(IcsExitDeclaration) && IcsExitDeclaration.table_exists?

    afls = Array(afls)
    ids = afls.map { |afl| afl.id.to_s }.reject(&:blank?).uniq
    tracenets = afls.map { |afl| target_farmer_text_value(afl&.tracenet_no) }.compact
    mobiles = afls.map { |afl| target_farmer_text_value(afl&.mobile_no) }.compact
    names = afls.map { |afl| target_farmer_text_value(afl&.farmer_name) }.compact
    id_numbers = afls.flat_map { |afl| [afl.aadhar, afl.qr_aadhar] }.map { |value| target_farmer_text_value(value) }.compact

    scope = IcsExitDeclaration.none
    scope = scope.or(IcsExitDeclaration.where(farm_id: ids)) if ids.any?
    scope = scope.or(IcsExitDeclaration.where(tracenet_no: tracenets)) if tracenets.any?
    scope = scope.or(IcsExitDeclaration.where(farmer_contact_no: mobiles)) if mobiles.any?
    scope = scope.or(IcsExitDeclaration.where(farmer_name: names)) if names.any?
    scope = scope.or(IcsExitDeclaration.where(id_number: id_numbers)) if id_numbers.any?

    scope.to_a.each_with_object({}) do |declaration, index|
      [
        declaration.farm_id,
        declaration.tracenet_no,
        declaration.farmer_contact_no,
        declaration.farmer_name,
        declaration.id_number,
        declaration.farmer_farm_information_id
      ].map { |value| target_farmer_text_value(value) }.reject(&:blank?).each do |key|
        index[key] ||= declaration
      end
    end
  end

  def target_farmer_declaration_for_afl(afl, declarations_by_key)
    return nil unless afl.present?

    keys = [
      afl.id,
      afl.tracenet_no,
      afl.mobile_no,
      afl.aadhar,
      afl.qr_aadhar,
      afl.farmer_name
    ].map { |value| target_farmer_text_value(value) }.reject(&:blank?)

    keys.each do |key|
      declaration = declarations_by_key[key]
      return declaration if declaration.present?
    end

    nil
  end

  def target_farmer_profile_from_records(id, afl = nil, farmer_info = nil, declaration = nil)
    {
      id: id.to_s,
      farmer_name: target_farmer_preferred_text(afl&.farmer_name, farmer_info&.farmer_name, declaration&.farmer_name).presence || "Farmer ##{id}",
      father_name: target_farmer_preferred_text(afl&.father_name, farmer_info&.father_mother_name),
      tracenet_no: target_farmer_preferred_text(afl&.tracenet_no, farmer_info&.tracenet_no, declaration&.tracenet_no),
      mobile_no: target_farmer_preferred_text(afl&.mobile_no, farmer_info&.farmer_contact_no, declaration&.farmer_contact_no),
      khasara_no: target_farmer_preferred_text(afl&.khasara_no, farmer_info&.khasra_no)
    }
  end

  def target_farmer_text_value(value)
    value.to_s.strip.presence
  end

  def target_farmer_preferred_text(*values)
    values.filter_map { |value| target_farmer_text_value(value) }.first
  end

  def normalize_location_values(target_mapping)
    fco_id, fco_name = parse_location_value(target_mapping.fco_id)
    ics_id, ics_name = parse_location_value(target_mapping.ics_id)
    village_values = parse_location_values(target_mapping.village_id)
    village_ids = village_values.map(&:first).reject(&:blank?).uniq
    village_names = village_values.map(&:last).reject(&:blank?).uniq

    target_mapping.fco_id = fco_id
    target_mapping.fco_name = fco_name
    target_mapping.ics_id = ics_id
    target_mapping.ics_name = ics_name
    target_mapping.village_id = if village_ids.blank?
                                  nil
                                else
                                  village_ids.one? ? village_ids.first : village_ids.to_json
                                end
    target_mapping.village_name = village_names.join(", ").presence
  end

  def afl_scope_for_location(fco_id, ics_id, village_id, fco_name = nil, ics_name = nil, village_name = nil)
    village_ids = Array(village_id).flat_map { |value| parse_location_values(value).map(&:first) }.reject(&:blank?).uniq
    village_names = Array(village_name).flat_map { |value| label_value_list(value) }.map(&:to_s).reject(&:blank?).uniq

    scope = filter_afl_location(Afl.all, :fco_id, :fco, fco_id, fco_name)
    scope = filter_afl_location(scope, :ics_id, :ics_name, ics_id, ics_name)
    filter_afl_location(scope, :village_id, :village_name, village_ids, village_names)
  end

  def filter_afl_location(scope, id_column, name_column, id_value, name_value)
    id_values = Array(id_value).flat_map { |value| location_value_list(value).map { |item| parse_location_value(item).first } }.reject(&:blank?).uniq
    label_values = location_label_variants(name_value, id_values)
    return scope.none if id_values.blank? && label_values.blank?

    conditions = []
    bind_values = {}
    if id_values.any?
      conditions << "#{Afl.connection.quote_column_name(id_column)} IN (:ids)"
      bind_values[:ids] = id_values
    end
    if label_values.any?
      conditions << "LOWER(TRIM(#{Afl.connection.quote_column_name(name_column)})) IN (:labels)"
      bind_values[:labels] = label_values.map(&:downcase)
    end

    scope.where(conditions.join(" OR "), bind_values)
  end

  def location_label_variants(*values)
    Array(values).flatten.flat_map { |value| label_value_list(value) }
      .flat_map do |label|
        text = label.to_s.strip
        [text, text.sub(/\s+-\s*\d+\z/, "").strip]
      end
      .reject(&:blank?)
      .uniq
  end

  def encoded_location_value(value, label)
    value = value.to_s
    label = label.to_s
    return value if label.blank?

    "#{value}||#{label}"
  end

  def parse_location_value(value)
    raw_value = value.to_s.strip
    id, label = raw_value.split("||", 2)
    if label.blank? && raw_value.match?(/\s-\s/)
      display_label, display_id = raw_value.rpartition(" - ").values_at(0, 2)
      if display_id.to_s.match?(/\A\d+\z/)
        id = display_id
        label = display_label
      end
    end

    [id.to_s.strip, label.to_s.strip.presence]
  end

  def parse_location_values(value)
    location_value_list(value)
      .map { |item| parse_location_value(item) }
      .reject { |id, _label| id.blank? }
      .uniq { |id, label| [id, label] }
  end

  def location_value_list(value)
    case value
    when Array
      value.flat_map { |item| location_value_list(item) }
    when String
      stripped = value.strip
      return [] if stripped.blank?

      if stripped.start_with?("[")
        parsed = JSON.parse(stripped)
        return location_value_list(parsed)
      end

      [stripped]
    else
      Array(value).flat_map { |item| location_value_list(item) }
    end
  rescue JSON::ParserError
    [value.to_s]
  end

  def village_ids_for(target_mapping)
    parse_location_values(target_mapping.village_id).map(&:first)
  end

  def label_value_list(value)
    location_value_list(value).flat_map { |item| item.to_s.split(",").map(&:strip) }
  end

  def normalized_afl_ids(ids)
    parsed_ids = ids.is_a?(String) ? JSON.parse(ids) : ids
    Array(parsed_ids).map(&:to_s).reject(&:blank?).uniq
  rescue JSON::ParserError
    []
  end

  def module_options(module_slug, *field_keys)
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    ModuleRecord.where(module_slug: module_slug)
      .order(created_at: :desc)
      .select { |record| record.data["status"].blank? || record.data["status"] == "Active" }
      .filter_map { |record| field_keys.filter_map { |field| record.data[field].presence }.first }
      .uniq
  end

  def first_present_data(record, *keys)
    data = record.respond_to?(:data) ? record.data : record
    data ||= {}
    keys.filter_map { |key| data[key].presence }.first
  end

  def main_activity_type_map
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    ModuleRecord.where(module_slug: "add-activity-group")
      .order(created_at: :desc)
      .select { |record| record.data["status"].blank? || record.data["status"] == "Active" }
      .filter_map do |record|
        main_activity = first_present_data(record, "main_activity_name", "activity_group_name", "activity_group", "group_name").to_s.strip
        next if main_activity.blank?

        {
          main_activity: main_activity,
          main_activity_type: first_present_data(record, "main_activity_type").presence || "Training"
        }
      end
      .uniq { |row| row[:main_activity].to_s.downcase }
  end

  def target_sub_activity_map
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    ModuleRecord.where(module_slug: "add-vrp-activity")
      .order(created_at: :desc)
      .select { |record| record.data["status"].blank? || record.data["status"] == "Active" }
      .filter_map do |record|
        main_activity = first_present_data(record, "main_activity", "activity_group", "activity_group_name", "main_activity_name").to_s.strip
        sub_activity = first_present_data(record, "sub_activity_name", "activity_name", "vrp_activity_name").to_s.strip
        next if main_activity.blank? || sub_activity.blank?

        { main_activity: main_activity, sub_activity: sub_activity }
      end
      .uniq
  end

  def target_sub_activity_options(main_activity)
    selected_main_activity = main_activity.to_s.strip.downcase
    return [] if selected_main_activity.blank?

    target_sub_activity_map
      .select { |row| row[:main_activity].to_s.strip.downcase == selected_main_activity }
      .filter_map { |row| row[:sub_activity].presence }
      .uniq
  end

  def visible_target_mappings
    return TargetMapping.all if admin_login?
    return TargetMapping.where(vrp_id: current_app_user["id"]) if non_admin_vrp_login?

    # Management users oversee a set of VRPs (the same set the dashboard shows). List every
    # mapping for those VRPs, not only the ones this user personally created, so the master
    # list reflects all assigned targets. Global-view users (admin/CFO) see everything.
    policy = dashboard_target_policy
    return TargetMapping.all if policy.send(:dashboard_global_view_user?)

    TargetMapping.where(vrp_id: policy.send(:dashboard_vrps).map(&:id))
  end

  def dashboard_filtered_target_mappings(scope)
    fco_ids = Array(params[:fco_id]).flatten.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    fcoc = params[:fcoc].to_s.strip
    ics = params[:ics].to_s.strip
    month = params[:month].to_s.strip
    main_activity = params[:main_activity].to_s.strip
    sub_activity = params[:sub_activity].to_s.strip
    vrp_id = params[:vrp_id].to_s.strip

    scope = scope.where("LOWER(BTRIM(COALESCE(fco_id, ''))) IN (:fco_ids)", fco_ids: fco_ids.map(&:downcase)) if fco_ids.any?
    if fcoc.present?
      normalized_fcoc = fcoc.downcase
      short_fcoc = normalized_fcoc.sub(/\Afco\s*-\s*c\s+/, "").strip
      scope = scope.where(
        "LOWER(BTRIM(COALESCE(fco_name, ''))) IN (:fcocs) OR LOWER(BTRIM(COALESCE(fco_id, ''))) IN (:fcocs)",
        fcocs: [normalized_fcoc, short_fcoc].uniq
      )
    end
    if ics.present?
      scope = scope.where(
        "LOWER(BTRIM(COALESCE(ics_name, ''))) = :ics OR LOWER(BTRIM(COALESCE(ics_id, ''))) = :ics",
        ics: ics.downcase
      )
    end
    scope = scope.where("LOWER(BTRIM(month_name)) = ?", month.downcase) if month.present?
    scope = scope.where("LOWER(BTRIM(main_activity_name)) = ?", main_activity.downcase) if main_activity.present?
    scope = scope.where("LOWER(BTRIM(activity_name)) = ?", sub_activity.downcase) if sub_activity.present?
    scope = scope.where(vrp_id: vrp_id) if vrp_id.present?
    scope
  end

  def target_mapping_rows(target_mappings)
    Array(target_mappings).map do |target|
      {
        target: target,
        main_activities: target_activity_values(target.main_activity_name),
        sub_activities: target_activity_values(target.activity_name),
        target_quantity: target.target_quantity,
        weekly_values: target.weekly_target_values,
        farmer_ids: normalized_afl_ids(target.afl_ids)
      }
    end
  end

  def visible_vrp_ics_mappings
    return VrpIcsMapping.all if admin_login?
    return VrpIcsMapping.where(vrp_id: current_app_user["id"]) if non_admin_vrp_login?

    VrpIcsMapping.where(created_by_type: current_app_user["record_type"], created_by_id: current_app_user["id"])
  end

  def current_app_user_id
    current_app_user&.dig("id")
  end

  def current_app_user_ids
    ([current_app_user_id] + legacy_current_app_user_ids).compact.uniq
  end

  def legacy_current_app_user_ids
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    username = current_app_user&.dig("username").to_s
    emails = current_app_user_emails
    return [] if username.blank? && emails.blank?

    ModuleRecord.where(module_slug: "new-user").select do |record|
      record.data["user_name"].to_s == username ||
        emails.include?(record.data["email"].to_s.strip.downcase)
    end.map(&:id)
  end

  def current_app_user_emails
    emails = [current_app_user&.dig("email")]

    if defined?(User) && User.table_exists?
      user = User.find_by(user_name: current_app_user&.dig("username")) || User.find_by(id: current_app_user_id)
      emails << user&.email
    end

    emails.compact_blank.map { |email| email.to_s.strip.downcase }.uniq
  end

  def assign_creator(record)
    record.created_by_type = current_app_user["record_type"]
    record.created_by_id = current_app_user["id"]
  end

  def edit_target_for_json
    return @edit_target_for_json if defined?(@edit_target_for_json)

    @edit_target_for_json = params[:edit_id].present? ? visible_target_mappings.find_by(id: params[:edit_id]) : nil
  end

  def admin_login?
    current_app_user["user_type"].to_s.strip.casecmp("admin").zero?
  end

  def non_admin_vrp_login?
    !admin_login? && current_app_user["record_type"].to_s == "Vrp"
  end

  def edit_payload(target)
    return {} unless target

    training_key = TRAINING_TARGET_FIELDS.key(target.activity_name.to_s)
    training_mode = training_key.present?

    {
      id: target.id,
      vrp_id: target.vrp_id.to_s,
      fco_id: encoded_location_value(target.fco_id, target.fco_name),
      ics_id: encoded_location_value(target.ics_id, target.ics_name),
      village_id: encoded_location_value(target.village_id, target.village_name),
      village_ids: encoded_location_values(target.village_id, target.village_name),
      month_name: target.month_name.to_s,
      completion_date: target.completion_date&.strftime("%Y-%m-%d"),
      main_activity_type: training_mode ? "Training" : main_activity_type_for(target.main_activity_name),
      main_activity_names: [target.main_activity_name.to_s].reject(&:blank?),
      activity_names: [target.activity_name.to_s].reject(&:blank?),
      target_quantity: target_number_value(target.target_quantity),
      new_farmer_target_quantity: Array(target.afl_ids).blank? && !training_mode ? target_number_value(target.target_quantity) : "",
      training_targets: TRAINING_TARGET_FIELDS.keys.index_with do |key|
        target_number_value(target.public_send("#{key}_target"))
      end,
      afl_ids: Array(target.afl_ids).map(&:to_s)
    }
  end

  def main_activity_type_for(main_activity_name)
    name = main_activity_name.to_s.strip.downcase
    return "Other" if name.blank?

    match = main_activity_type_map.find { |row| row[:main_activity].to_s.strip.downcase == name }
    match&.dig(:main_activity_type).presence || "Training"
  end

  def target_number_value(value)
    return "" if value.blank?

    BigDecimal(value.to_s).to_s("F").sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, '\\1')
  rescue ArgumentError
    value.to_s
  end

  def encoded_location_values(values, labels)
    ids = location_value_list(values)
    label_values = labels.to_s.split(",").map(&:strip)

    ids.map.with_index do |id, index|
      encoded_location_value(id, label_values[index])
    end
  end
  def training_target_opg_error
    targets = target_mapping_params[:training_targets]
    return unless targets.respond_to?(:[])

    supplied = TRAINING_TARGET_FIELDS.keys.select { |key| targets[key].present? }
    return "Training target values must be non-negative whole numbers." if supplied.any? { |key| integer_plan_value(targets[key]).nil? }
    return if supplied.empty?
    return "Please enter OPG Training before allocating the four training targets." if targets["opg_training"].blank?

    opg = integer_plan_value(targets["opg_training"])
    breakdown = OPG_BREAKDOWN_KEYS.sum { |key| integer_plan_value(targets[key]).to_i }
    return if breakdown == opg

    "General Training/Meeting, Input Demo INM, Input Demo PM aur FFS ka total (#{breakdown}) OPG Training (#{opg}) ke equal hona chahiye; usse zyada nahi ho sakta."
  end


  def dashboard_target_policy
    policy = ModulesController.new
    policy.request = request
    policy.instance_variable_set(:@current_app_user, current_app_user)
    policy
  end


end
