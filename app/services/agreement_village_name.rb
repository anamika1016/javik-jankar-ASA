class AgreementVillageName
  def self.call(vrp)
    values = Array(vrp.village_ids).map { |value| value.to_s.strip }.reject(&:blank?)
    if values.empty?
      values = [vrp.vrp_profile&.village_id.to_s].reject { |value| value.blank? || value == "0" }
    end
    values.map { |value| label(value) }.compact_blank.uniq.join(", ").presence || "-"
  end

  def self.label(value)
    id, name = value.split("||", 2)
    return name.strip if name.present?
    return value unless id.match?(/\A\d+\z/)

    records = ModuleRecord.where(module_slug: ["village-master", "lg-directory-list"])
    record = records.find_by(id: id)
    name = village_label(record)
    return name if name.present?

    record = records.where("data::jsonb ->> 'village_id' = :id OR data::jsonb ->> 'village_code' = :id", id: id).first
    name = village_label(record)
    return name if name.present?

    [TargetMapping, VrpIcsMapping, Afl].each do |model|
      name = model.where(village_id: id).where.not(village_name: [nil, ""]).order(:id).pick(:village_name)
      return name if name.present?
    end
    value
  end

  def self.village_label(record)
    data = record&.data || {}
    [data["village_name"], data["village"], data["name"], data["title"]].find(&:present?)
  end
end
