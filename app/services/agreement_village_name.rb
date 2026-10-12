class AgreementVillageName
  def preload(vrps)
    ids = vrps.flat_map { |vrp| self.class.values(vrp) }
      .select { |value| !value.include?("||") && value.match?(/\A\d+\z/) }.uniq
    @labels = {}
    return self if ids.empty?

    records = ModuleRecord.where(module_slug: ["village-master", "lg-directory-list"])
    rows = records.where(id: ids).or(records.where(
      "data::jsonb ->> 'village_id' IN (:ids) OR data::jsonb ->> 'village_code' IN (:ids)", ids: ids
    )).order(:id).to_a
    primary = rows.index_by { |record| record.id.to_s }
    aliases = {}
    rows.each do |record|
      %w[village_id village_code].each { |key| aliases[record.data[key].to_s] ||= record }
    end
    ids.each do |id|
      name = self.class.village_label(primary[id.to_i.to_s])
      name = self.class.village_label(aliases[id]) unless name.present?
      @labels[id] = name if name.present?
    end
    [TargetMapping, VrpIcsMapping, Afl].each do |model|
      missing = ids.reject { |id| @labels.key?(id) }
      break if missing.empty?
      first_names = {}
      model.where(village_id: missing).where.not(village_name: [nil, ""]).order(:id)
        .pluck(:village_id, :village_name).each { |id, name| first_names[id.to_s] ||= name }
      missing.each { |id| @labels[id] = first_names[id] if first_names[id].present? }
    end
    ids.each { |id| @labels[id] = id unless @labels.key?(id) }
    self
  end

  def call(vrp)
    self.class.values(vrp).map do |value|
      @labels&.key?(value) ? @labels[value] : self.class.label(value)
    end.compact_blank.uniq.join(", ").presence || "-"
  end

  def self.call(vrp)
    values(vrp).map { |value| label(value) }.compact_blank.uniq.join(", ").presence || "-"
  end

  def self.values(vrp)
    values = Array(vrp.village_ids).map { |value| value.to_s.strip }.reject(&:blank?)
    if values.empty?
      values = [vrp.vrp_profile&.village_id.to_s].reject { |value| value.blank? || value == "0" }
    end
    values
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
