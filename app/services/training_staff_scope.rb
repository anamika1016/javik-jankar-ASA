# Resolves training staff and approvers from the owning FCO, never from edited fields.
class TrainingStaffScope
  ROLE_KEYS = %w[role role_name stakeholder_role user_management_role person_type].freeze
  OFFICE_KEYS = %w[fcoc fcoc_name office_name parent_office office].freeze

  def self.normalize(value)
    value.to_s.downcase.gsub(/\Afco\s*-?\s*c\s*/, "").gsub(/\s+/, " ").strip
  end

  def self.office_for(data, actor = {})
    vrp_id = data.values_at("jeevika_jankar_id", "vrp_id", "select_vrp").find(&:present?)
    vrp = Vrp.find_by(id: vrp_id) if vrp_id.present?
    target_id = data["target_mapping_id"].presence || Array(data["target_mapping_ids"]).first
    target = TargetMapping.find_by(id: target_id) if target_id.present?
    vrp&.fcoc.presence || target&.fco_name.presence ||
      data.values_at("fco_name", "trainee_department", "fcoc_name", "fcoc").find(&:present?) ||
      actor.values_at(*OFFICE_KEYS).find(&:present?)
  end

  # Callers processing many revisions can pass a request-local catalogue. It keeps the
  # same staff selection rules while avoiding a complete User/new-user scan per revision.
  def self.staff(office, kind, catalogue: nil)
    return [] if office.blank?

    pattern = { cluster_coordinator: /cluster/i, agronomist: /agronom|agricultural specialist/i,
                fcoc: /fco\s*-?\s*c|\Afco\z|source/i }.fetch(kind)
    candidates = catalogue || staff_catalogue
    candidates.select do |data|
      active = data["status"].blank? || data["status"].to_s.casecmp("Active").zero?
      active && !%w[deleted is_deleted discarded].any? { |key| %w[true 1 yes].include?(data[key].to_s.downcase) } &&
        ROLE_KEYS.any? { |key| data[key].to_s.match?(pattern) } &&
        OFFICE_KEYS.any? { |key| data[key].present? && normalize(data[key]) == normalize(office) }
    end
  end

  def self.staff_catalogue
    # Do not instantiate password/profile columns while approval routing only needs
    # identity, role, office and display-name fields.
    user_columns = (['id', 'first_name', 'last_name', 'user_name', 'status'] + ROLE_KEYS + OFFICE_KEYS)
      .uniq & User.column_names
    User.select(*user_columns).map { |user| user.attributes.merge("record_type" => "User") } +
      ModuleRecord.where(module_slug: "new-user").select(:id, :data).map do |record|
        record.data.merge("id" => record.id, "record_type" => "ModuleRecord")
      end
  end

  def self.name(data)
    [data["first_name"], data["last_name"]].compact_blank.join(" ").gsub(/\s+/, " ").strip.presence || data["user_name"]
  end

  def self.options(office, kind, catalogue: nil)
    ["N/A"] + staff(office, kind, catalogue: catalogue).filter_map { |data| name(data).presence }.uniq { |name| normalize(name) }.sort
  end
end
