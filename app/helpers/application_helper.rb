module ApplicationHelper
  def farmer_farm_information_select_options
    return [] unless "FarmerFarmInformation".safe_constantize&.table_exists?

    FarmerFarmInformation
      .order(:farm_id, :farmer_name)
      .limit(1_000)
      .map { |record| [farmer_farm_information_option_label(record), record.id] }
  end

  def farmer_farm_information_option_label(record)
    [record.farm_id, record.farmer_name, record.ics_name].compact_blank.join(" - ")
  end

  def linked_farmer_farm_id(record)
    record.farmer_farm_information&.farm_id.presence || "-"
  end

  def linked_farmer_name(record)
    record.farmer_farm_information&.farmer_name.presence || "-"
  end

  def linked_ics_name(record)
    record.farmer_farm_information&.ics_name.presence || "-"
  end

  SIDEBAR_SECTIONS = [
    {
      title: "LG Directory",
      icon: "▦",
      links: [
        ["All List", :module, "lg-directory-list"],
        ["State Entry", :module, "state-master"],
        ["District Entry", :module, "district-master"],
        ["Block Entry", :module, "block-master"],
        ["GP Entry", :module, "gram-panchayat-master"],
        ["Village Entry", :module, "village-master"],
        ["Month Entry", :module, "month-master"]
      ]
    },
    {
      title: "Stakeholder",
      icon: "▩",
      links: [
        ["Stakeholder Name", :module, "stakeholder-master"],
        ["Stakeholder Person Type", :module, "stakeholder-role"],
        ["Role", :module, "role-name"]
      ]
    },
    {
      title: "Office Setup",
      icon: "▧",
      links: [
        ["Parent Office Add", :module, "parent-office-add"],
        ["Office Category Add", :module, "office-category-add"],
        ["Sub Office Add", :module, "office-mapping-add"]
      ]
    },
    {
      title: "Activity Setup",
      icon: "▤",
      links: [
        ["Project Add", :module, "project-master"],
        ["Main Activity", :module, "add-activity-group"],
        ["Main Activity List", :module, "activity-group-list"],
        ["Sub Activity", :module, "add-vrp-activity"],
        ["Sub Activity List", :module, "vrp-activity-list"]
      ]
    },
    {
      title: "User Register",
      icon: "▩",
      links: [
        ["All User", :route, :users_path],
        ["Registration", :route, :new_user_path]
      ]
    },
    {
      title: "User Mapping",
      icon: "▧",
      links: [
        ["User Hierarchy Mapping", :module, "user-hierarchy-mapping"],
        ["Cluster Incharge Under Jeevika Jankar User", :module, "user-hierarchy-list"]
      ]
    },
    {
      title: "Resource Person Type",
      icon: "▧",
      links: [
        # ["Resource Person Type", :module, "role-management"],
        # ["User Management Person Type", :module, "user-management-role"],
        # ["Person Type", :module, "person-type"],
        ["Access Control", :module, "access-control"],
        ["Access Control List", :module, "access-control-list"]
      ]
    },
    {
      title: "Jeevika Jankar Registration",
      icon: "▥",
      links: [
        ["Add Jeevika Jankar Type", :module, "add-vrp-type"],
        ["Jeevika Jankar Registration", :route, :new_vrp_path],
        ["Jeevika Jankar List", :route, :vrps_path],
        ["Jeevika Jankar Approval Queue", :route, :approvals_vrps_path],
        ["Jeevika Jankar Approval Form", :module, "approval-master"],
        ["Jeevika Jankar Approval List", :module, "approval-list"],
        ["Accepted Agreement by Jeevika Jankar", :route, :vrp_agreements_path]
      ]
    },
    # {
    #   title: "Bill Management",
    #   icon: "▧",
    #   links: [
    #     ["Bill Entry", :module, "vrp-bill-add"],
    #     ["Bill List", :module, "vrp-bill-list"]
    #   ]
    # },
    {
      title: "Weekly Target",
      icon: "▨",
      links: [
        ["Weekly Activity Progress Report", :route, :weekly_activity_target_report_path],
        ["Target Status List", :route, :farmer_training_target_status_path]
      ]
    },
    {
      title: "Target Mapping",
      icon: "▤",
      links: [
        ["AFL Upload", :route, :afls_path],
        # ["VRP ICS Mapping", :route, :vrp_ics_mappings_path],
        ["Target Mapping Master", :route, :target_mappings_path]
      ]
    },
    {
      title: "Farmer Target",
      icon: "▥",
      links: [
        # ["Farmer Training Topic Mapping", :module, "training-topic-mapping"],
        ["Farmer Training Form", :module, "training-form"],
        ["Farmer Training Form List", :module, "training-form-list"],
        ["Farmer Participation Report", :route, :farmer_participation_report_path],
        ["Seed Distribution Target", :module, "seed-distribution-target"],
        ["Seed Distribution Target List", :module, "seed-distribution-target-list"],
        ["PAPL360 Target", :module, "papl360-target"],
        ["PAPL360 Target List", :module, "papl360-target-list"],
        ["Add Farmer Form", :module, "add-farmer-form"]
      ]
    },
    # {
    #   title: "ICS MASTER",
    #   icon: "▥",
    #   links: [
    #     ["ICS Master", :module, "ics-master"]
    #   ]
    # },
    {
      title: "Farmer Farm Information",
      icon: "▥",
      links: [
        ["Farmer Farm Information", :route, :farmer_farm_information_path],
        ["All Basic Detail List", :route, :list_farmer_farm_information_path],
        ["Farm Map (lat long gps)", :route, :farm_map_farmer_farm_information_path],
        ["Crop Map Session Wise Farm Map (lat long gps)", :route, :crop_map_session_wise_farmer_farm_information_path],
        ["Farm-Crop-Area Details", :route, :farm_crop_area_details_path],
        ["Seed & Planting Material", :route, :seed_planting_materials_path],
        ["Soil Conditioners & Fertility Input Records", :route, :soil_conditioner_fertility_input_records_path],
        ["On Farm Input Records", :route, :on_farm_input_records_path],
        ["Disease, Insects, Pests & Weed Management Record", :route, :disease_pest_weed_management_records_path],
        ["Contamination Control Records", :route, :contamination_control_records_path],
        ["Records of Production & Harvest Details", :route, :production_harvest_details_path],
        ["Post Harvest, Handling & Storage Area", :route, :post_harvest_handling_storage_records_path],
        ["Sale Record", :route, :sale_records_path],
        ["Dispatch Record", :route, :dispatch_records_path],
        ["Application Format for Exit of Farmer from ICS", :route, :ics_exit_declaration_farmer_farm_information_path]
      ]
    },
    {
      title: "Jeevika Jankar Bill",
      icon: "▧",
      links: [
        ["Bill Process", :module, "jeevika-jankar-bill-process"],
        ["Bill List", :module, "jeevika-jankar-bill-list"],
        ["Payment List", :module, "jeevika-jankar-payment-list"],
        ["Payment List Detail", :module, "jeevika-jankar-payment-list-detail"],
        ["Completed Payment List", :module, "jeevika-jankar-completed-payment-list"]
      ]
    },
  ].freeze

  def sidebar_sections
    return @sidebar_sections if defined?(@sidebar_sections)
    return visible_vrp_sidebar_sections if vrp_login_user?

    allowed_keys = allowed_sidebar_keys
    return @sidebar_sections = SIDEBAR_SECTIONS if allowed_keys.nil?

    @sidebar_sections = SIDEBAR_SECTIONS.filter_map do |section|
      allowed_links = section[:links].select { |link| allowed_keys.include?(sidebar_access_key(link)) }
      section.merge(links: allowed_links) if allowed_links.any?
    end
  end

  def sidebar_link_path(link)
    _label, type, target = link
    type == :module ? module_path(target) : public_send(target)
  end

  def sidebar_link_active?(link)
    _label, type, target = link

    if type == :module
      request.path.include?(target)
    else
      return request.path.start_with?(public_send(target)) if target == :ics_exit_declaration_farmer_farm_information_path

      request.path == public_send(target)
    end
  end

  def sidebar_section_active?(section)
    section[:links].any? { |link| sidebar_link_active?(link) }
  end

  def sidebar_access_key(link)
    label, _type, _target = link
    {
      "Jeevika Jankar Registration" => "vrp-registration",
      "Jeevika Jankar List" => "vrp-list",
      "Jeevika Jankar Approval Queue" => "vrp-approval-queue",
      "Jeevika Jankar Approval Form" => "vrp-approval-form",
      "Jeevika Jankar Approval List" => "vrp-approval-list",
      "Jeevika Jankar Targets" => "vrp-targets"
    }.fetch(label.to_s, label.parameterize)
  end

  def resource_person_label(label)
    {
      "Stakeholder" => "Stakeholder Category",
      "Role" => "Role",
      "Role Name" => "Role Name",
      "Stakeholder Role" => "Stakeholder Person Type",
      "User Management Role" => "User Management Person Type",
      "Person Type" => "Person Type",
      "Parent Office" => "Parent Office Name",
      "Sub Office Name" => "Sub Office Name",
      "ICS / Block" => "ICS Name",
      "Gram Name" => "Village Name",
      "VRP Type" => "Jeevika Jankar Type",
      "Select VRP Type" => "Select Jeevika Jankar Type",
      "VRP Type Name" => "Jeevika Jankar Type Name",
      "Jeevika Jankar Type" => "Jeevika Jankar Type",
      "Jeevika Jankar Type Name" => "Jeevika Jankar Type Name",
      "Activity Group" => "Main Activity",
      "Activity Group Name" => "Main Activity Name",
      "Activity Name" => "Sub Activity Name",
      "VRP Activity" => "Sub Activity",
      "Farmer Count" => "AFL Farmer Count",
      "VRP" => "Jeevika Jankar",
      "Select VRP" => "Select Jeevika Jankar",
      "VRP Name" => "Jeevika Jankar Name",
      "VRP Registration" => "Jeevika Jankar Registration",
      "VRP List" => "Jeevika Jankar List",
      "VRP Approval Queue" => "Jeevika Jankar Approval Queue",
      "VRP Approval Form" => "Jeevika Jankar Approval Form",
      "VRP Approval List" => "Jeevika Jankar Approval List",
      "VRP Targets" => "Jeevika Jankar Targets"
    }.fetch(label.to_s, label)
  end

  def allowed_sidebar_keys
    return @allowed_sidebar_keys if defined?(@allowed_sidebar_keys)
    return nil unless current_app_user.present?
    return nil if admin_access_user?
    return @allowed_sidebar_keys = [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    cache_version = ModuleRecord.where(module_slug: "access-control").maximum(:updated_at)&.to_i
    cache_key = [
      "allowed_sidebar_keys",
      current_app_user["id"],
      current_app_user["username"],
      cache_version
    ]

    @allowed_sidebar_keys = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      compute_allowed_sidebar_keys
    end
  end

  def compute_allowed_sidebar_keys
    access_records = ModuleRecord
      .where(module_slug: "access-control")
      .order(created_at: :desc)
      .select { |record| record.data["status"].blank? || record.data["status"].to_s.casecmp("Active").zero? }
      .select do |record|
        record_stakeholder = record.data["stakeholder_name"].presence || record.data["stakeholder"]
        stakeholder_match = access_value_matches?(record_stakeholder, current_app_user["stakeholder"])
        record_stakeholder_role = record.data["stakeholder_role"].presence || record.data["stakeholder_person_type"]
        stakeholder_role_match = access_value_matches?(record_stakeholder_role, current_app_user["stakeholder_role"])
        record_role = record.data["role"].presence || record.data["role_name"]
        role_match = access_value_matches?(record_role, current_app_user["role"])
        record_role_name = record.data["role"].present? ? record.data["role_name"] : nil
        role_name_match = access_value_matches?(record_role_name, current_app_user["role_name"])
        record_user_management_role = record.data["user_management_role"].presence || record.data["user_management_person_type"]
        user_management_role_match = access_value_matches?(record_user_management_role, current_app_user["user_management_role"])
        record_person_type = record.data["person_type"]
        person_type_match = access_value_matches?(record_person_type, current_app_user["person_type"])
        record_vrp_type = record.data["jeevika_jankar_type"].presence || record.data["vrp_type"].presence || record.data["select_vrp_type"]
        vrp_type_match = access_value_matches_any?(record_vrp_type, current_app_user["vrp_types"])
        can_view = record.data["can_view"].blank? || record.data["can_view"].to_s.casecmp("Yes").zero?
        next can_view && record_vrp_type.present? && vrp_type_match if vrp_login_user?

        stakeholder_match && stakeholder_role_match && role_match && role_name_match && user_management_role_match && person_type_match && vrp_type_match && can_view
      end

    access_records.flat_map do |record|
      access_values(record.data["sub_module_names"].presence || record.data["sub_module_name"])
        .flat_map { |name| sidebar_access_name_keys(name) }
    end.uniq
  end

  def sidebar_access_name_keys(name)
    keys = [name.presence&.parameterize].compact
    keys << "vrp-approval-queue" if ["VRP Approval", "Jeevika Jankar Approval", "Jeevika Jankar Approval Queue"].include?(name.to_s.strip)
    keys << "vrp-approval" if ["VRP Approval Queue", "Jeevika Jankar Approval Queue"].include?(name.to_s.strip)
    if ["VRP Registration", "Jeevika Jankar Registration"].include?(name.to_s.strip)
      keys.concat(["vrp-registration", "jeevika-jankar-registration"])
    end
    if ["VRP List", "Jeevika Jankar List"].include?(name.to_s.strip)
      keys.concat(["vrp-list", "jeevika-jankar-list"])
    end
    if ["VRP Approval Form", "Jeevika Jankar Approval Form"].include?(name.to_s.strip)
      keys.concat(["vrp-approval-form", "jeevika-jankar-approval-form", "approval-master"])
    end
    if ["VRP Approval List", "Jeevika Jankar Approval List"].include?(name.to_s.strip)
      keys.concat(["vrp-approval-list", "jeevika-jankar-approval-list", "approval-list"])
    end
    if ["VRP Type", "Add Jeevika Jankar Type", "Jeevika Jankar Type"].include?(name.to_s.strip)
      keys.concat(["vrp-type", "add-jeevika-jankar-type", "jeevika-jankar-type"])
    end
    if ["Farmer Training", "Farmer Target"].include?(name.to_s.strip)
      keys.concat(["farmer-training", "farmer-target", "farmer-participation-report", "seed-distribution-target", "papl360-target", "add-farmer-form"])
    end
    if ["Farmer Training Form", "Farmer Target Form"].include?(name.to_s.strip)
      keys.concat(["farmer-training-form", "farmer-target-form", "seed-distribution-target", "papl360-target"])
    end
    if ["Farmer Training Form List", "Farmer Target Form List"].include?(name.to_s.strip)
      keys.concat(["farmer-training-form-list", "farmer-target-form-list", "farmer-participation-report", "seed-distribution-target-list", "papl360-target-list"])
    end
    if ["Seed Distribution Target", "Seed Distribution Target Form"].include?(name.to_s.strip)
      keys.concat(["seed-distribution-target", "seed-distribution-target-form", "seed-distribution-target-list"])
    end
    if ["Seed Distribution Target List"].include?(name.to_s.strip)
      keys.concat(["seed-distribution-target-list"])
    end
    if ["PAPL360 Target", "PAPL360 Targate", "PAPL360 Target Form"].include?(name.to_s.strip)
      keys.concat(["papl360-target", "papl360-targate", "papl360-target-form", "papl360-target-list", "add-farmer-form"])
    end
    if ["PAPL360 Target List", "PAPL360 Targate List"].include?(name.to_s.strip)
      keys.concat(["papl360-target-list", "papl360-targate-list", "add-farmer-form"])
    end
    if ["Add Farmer Form"].include?(name.to_s.strip)
      keys.concat(["add-farmer-form"])
    end
    if ["Farmer Farm Information", "Farmer FARM Information", "Farmer_FARM _Information"].include?(name.to_s.strip)
      keys.concat(["farmer-farm-information", "application-format-for-exit-of-farmer-from-ics"])
    end
    if ["All Basic Detail List", "All Land List", "Land List", "Farmer Farm Information List"].include?(name.to_s.strip)
      keys.concat(["all-basic-detail-list", "all-land-list", "land-list", "farmer-farm-information-list"])
    end
    if ["Farm Map", "Farm Map (lat long gps)", "FRAM MAP (lat long gps)"].include?(name.to_s.strip)
      keys.concat(["farm-map", "farm-map-lat-long-gps", "fram-map-lat-long-gps"])
    end
    if ["Crop Map Session Wise Farm Map", "Crop Map Session Wise Farm Map (lat long gps)"].include?(name.to_s.strip)
      keys << "crop-map-session-wise-farm-map-lat-long-gps"
    end
    if ["Farm-Crop-Area Details", "Farm Crop Area Details"].include?(name.to_s.strip)
      keys << "farm-crop-area-details"
    end
    if ["Seed & Planting Material", "Seed Planting Material"].include?(name.to_s.strip)
      keys << "seed-planting-material"
    end
    if ["Soil Conditioners & Fertility Input Records", "Soil Conditioner Fertility Input Records"].include?(name.to_s.strip)
      keys << "soil-conditioners-fertility-input-records"
    end
    if ["On Farm Input Records", "Record of on farm input"].include?(name.to_s.strip)
      keys << "on-farm-input-records"
    end
    if ["Disease, Insects, Pests & Weed Management Record", "Disease Insects Pests Weed Management Record"].include?(name.to_s.strip)
      keys << "disease-insects-pests-weed-management-record"
    end
    if ["Contamination Control Records", "Contamination Control"].include?(name.to_s.strip)
      keys << "contamination-control-records"
    end
    if ["Target Mapping Master", "Target Mapping", "VRP Targets", "Target Mapped JJ"].include?(name.to_s.strip)
      keys.concat(["target-mapping-master", "target-mapping", "vrp-targets", "target-mapped-jj"])
    end
    if ["Bill Process", "Jeevika Jankar Bill", "Jeevika Jankar Bill Process"].include?(name.to_s.strip)
      keys.concat(["bill-process", "jeevika-jankar-bill", "jeevika-jankar-bill-process"])
    end
    if ["Bill List", "Jeevika Jankar Bill List"].include?(name.to_s.strip)
      keys.concat(["bill-list", "jeevika-jankar-bill-list", "payment-list", "jeevika-jankar-payment-list", "payment-list-detail", "jeevika-jankar-payment-list-detail", "completed-payment-list", "jeevika-jankar-completed-payment-list"])
    end
    if ["Payment List", "Jeevika Jankar Payment List"].include?(name.to_s.strip)
      keys.concat(["payment-list", "jeevika-jankar-payment-list", "payment-list-detail", "jeevika-jankar-payment-list-detail", "completed-payment-list", "jeevika-jankar-completed-payment-list"])
    end
    if ["Payment List Detail", "Jeevika Jankar Payment List Detail"].include?(name.to_s.strip)
      keys.concat(["payment-list-detail", "jeevika-jankar-payment-list-detail", "completed-payment-list", "jeevika-jankar-completed-payment-list"])
    end
    if ["Completed Payment List", "Jeevika Jankar Completed Payment List"].include?(name.to_s.strip)
      keys.concat(["completed-payment-list", "jeevika-jankar-completed-payment-list"])
    end
    keys.uniq
  end

  def access_values(value)
    Array(value)
      .flat_map { |item| item.to_s.split(",") }
      .map(&:strip)
      .reject(&:blank?)
  end

  def access_value_matches?(record_value, user_value)
    record_value.blank? || (user_value.present? && record_value.to_s.strip.casecmp(user_value.to_s.strip).zero?)
  end

  def access_value_matches_any?(record_value, user_values)
    return true if record_value.blank?

    Array(user_values).any? { |value| value.to_s.strip.casecmp(record_value.to_s.strip).zero? }
  end

  def admin_access_user?
    current_app_user["user_type"].to_s.strip.casecmp("admin").zero?
  end

  def vrp_login_user?
    current_app_user&.dig("record_type").to_s == "Vrp"
  end

  def current_vrp_identity_url
    return unless vrp_login_user?

    vrp_id = current_app_user&.dig("id").presence
    return if vrp_id.blank?

    "http://krai.ploughmanagro.com/VRP_ID:#{vrp_id}"
  end

  def vrp_sidebar_sections
    [
      {
        title: "Target Mapping",
        icon: "▨",
        links: [
          ["Target Mapped JJ", :route, :target_mappings_path]
        ]
      },
      {
        title: "Farmer Target",
        icon: "▥",
      links: [
        ["Farmer Training Form", :module, "training-form"],
        ["Farmer Training Form List", :module, "training-form-list"],
        ["Farmer Participation Report", :route, :farmer_participation_report_path],
        ["Seed Distribution Target", :module, "seed-distribution-target"],
        ["Seed Distribution Target List", :module, "seed-distribution-target-list"],
        ["PAPL360 Target", :module, "papl360-target"],
          ["PAPL360 Target List", :module, "papl360-target-list"],
          ["Add Farmer Form", :module, "add-farmer-form"]
        ]
      },
      {
        title: "Jeevika Jankar Bill",
        icon: "▧",
        links: [
          ["Bill Process", :module, "jeevika-jankar-bill-process"],
          ["Bill List", :module, "jeevika-jankar-bill-list"],
          ["Payment List", :module, "jeevika-jankar-payment-list"],
          ["Payment List Detail", :module, "jeevika-jankar-payment-list-detail"],
          ["Completed Payment List", :module, "jeevika-jankar-completed-payment-list"]
        ]
      }
    ]
  end

  def visible_vrp_sidebar_sections
    allowed_keys = allowed_sidebar_keys
    sections = vrp_sidebar_sections

    sections.filter_map do |section|
      if section[:links].any? { |link| link.first == "Target Mapped JJ" }
        next section
      end

      next if allowed_keys.blank?

      allowed_links = section[:links].select { |link| allowed_keys.include?(sidebar_access_key(link)) }
      section.merge(links: allowed_links) if allowed_links.any?
    end
  end

  def current_stakeholder
    @current_stakeholder ||= matching_stakeholder_record("stakeholder-master") || active_stakeholder_records("stakeholder-master").first
  end

  def current_stakeholder_profile
    @current_stakeholder_profile ||= matching_stakeholder_record("stakeholder-profile") || active_stakeholder_records("stakeholder-profile").first
  end

  def app_display_name
    @app_display_name ||= current_stakeholder&.data&.[]("stakeholder_name_in_english").presence ||
      current_stakeholder&.data&.[]("stakeholder_name").presence ||
      ENV.fetch("APP_NAME", "VRP")
  end

  def app_logo_path
    @app_logo_path ||= matching_stakeholder_record("stakeholder-master")&.data&.[]("logo_upload").presence ||
      matching_stakeholder_record("stakeholder-profile")&.data&.[]("logo_upload").presence ||
      current_stakeholder&.data&.[]("logo_upload").presence ||
      current_stakeholder_profile&.data&.[]("logo_upload").presence ||
      "/icon.svg"
  end

  def active_stakeholder_records(module_slug)
    return [] unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    @active_stakeholder_records ||= {}
    @active_stakeholder_records[module_slug] ||= ModuleRecord
      .where(module_slug: module_slug)
      .order(updated_at: :desc)
      .select { |record| record.data["status"].blank? || record.data["status"] == "Active" }
  end

  def matching_stakeholder_record(module_slug)
    @matching_stakeholder_records ||= {}
    return @matching_stakeholder_records[module_slug] if @matching_stakeholder_records.key?(module_slug)

    names = current_user_stakeholder_names
    return @matching_stakeholder_records[module_slug] = nil if names.blank?

    @matching_stakeholder_records[module_slug] = active_stakeholder_records(module_slug).detect do |record|
      names.any? { |stakeholder_name| stakeholder_record_matches?(record, stakeholder_name) }
    end
  end

  def current_user_stakeholder_names
    return @current_user_stakeholder_names if defined?(@current_user_stakeholder_names)

    names = [current_app_user&.dig("stakeholder")]
    username = current_app_user&.dig("username").to_s

    if defined?(User) && User.table_exists?
      user = User.find_by(user_name: username) || User.find_by(id: current_app_user&.dig("id"))
      names << user&.stakeholder
    end

    if defined?(ModuleRecord) && ModuleRecord.table_exists? && username.present?
      legacy_user = ModuleRecord
        .where(module_slug: "new-user")
        .where("data::jsonb ->> 'user_name' = ?", username)
        .order(updated_at: :desc)
        .first
      names << legacy_user&.data&.[]("stakeholder")
    end

    @current_user_stakeholder_names = names.compact_blank.map { |name| name.to_s.strip }.uniq
  rescue ActiveRecord::StatementInvalid
    legacy_user = ModuleRecord
      .where(module_slug: "new-user")
      .order(updated_at: :desc)
      .detect { |record| record.data["user_name"].to_s == username }
    names << legacy_user&.data&.[]("stakeholder")
    @current_user_stakeholder_names = names.compact_blank.map { |name| name.to_s.strip }.uniq
  end

  def stakeholder_record_matches?(record, stakeholder_name)
    normalized_stakeholder = normalize_stakeholder_name(stakeholder_name)
    return false if normalized_stakeholder.blank?

    values = [
      record.data["stakeholder_name_in_english"],
      record.data["stakeholder_name_in_hindi"],
      record.data["stakeholder_name"],
      record.data["profile_name"]
    ]

    values.compact.any? do |value|
      normalized_value = normalize_stakeholder_name(value)
      normalized_value == normalized_stakeholder ||
        normalized_value.split.include?(normalized_stakeholder) ||
        normalized_stakeholder.split.include?(normalized_value)
    end
  end

  def normalize_stakeholder_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end
end
