class AgreementVillageName
  def preload(vrps)
    ids = vrps.flat_map { |vrp| self.class.values(vrp) }
      .select { |value| !value.include?("||") && value.match?(/\A\d+\z/) }.uniq
    @labels = {}
    return self if ids.empty?

    rows = self.class.village_rows_for(ids)
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

    name = village_label(village_rows_for([id]).find { |row| row.id.to_s == id })
    return name if name.present?

    name = village_label(village_rows_for([id]).first)
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

  # Village rows matching these ids, by primary key or by the village id / code
  # carried in the payload.
  #
  # Served off lg_villages: the id is its primary key and village_code is an
  # indexed column, where the module_records version scanned every row's JSON
  # for both.
  #
  # Deliberately not scoped to active rows: an agreement still has to show the
  # name of a village since retired.
  def self.village_rows_for(ids)
    values = Array(ids).map(&:to_s)
    return [] if values.empty?

    if defined?(ModuleMirror) && ModuleMirror.covers?("village-master")
      return LgVillage
        .where(id: values)
        .or(LgVillage.where("data ->> 'village_id' IN (:ids) OR village_code IN (:ids)", ids: values))
        .order(:id).to_a
    end

    records = ModuleEntry.where(module_slug: ["village-master", "lg-directory-list"])
    records.where(id: values).or(records.where(
      "data::jsonb ->> 'village_id' IN (:ids) OR data::jsonb ->> 'village_code' IN (:ids)", ids: values
    )).order(:id).to_a
  end
end
