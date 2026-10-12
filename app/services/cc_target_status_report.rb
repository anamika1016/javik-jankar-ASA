class CcTargetStatusReport
  CC_NAME_KEYS = %w[cluster_coordinator_name cluster_incharge cluster_coordinator].freeze
  # "N/A" is a real option in the Cluster Coordinator dropdown, so selecting it
  # means "no Cluster Coordinator" exactly like clearing the field does.
  CC_NAME_NONE = /\A(n\.?\/?a\.?|none|nil|null|-+)\z/i
  HEADERS = ["month", "fco_id", "fpo_name", "cluster_incharge", "jj_names", "target", "achievement", "status"].freeze

  def initialize(calculator:, month: nil, fco: nil)
    @fco_names = {}
    @calculator = calculator
    filters = calculator.respond_to?(:params) && calculator.request ? calculator.params : {}
    @month = (month || (filters.key?(:month) ? filters[:month] : DashboardDefaults.month)).to_s.strip
    @fco = (fco || filters[:fcoc] || filters[:fco] || filters[:fco_id]).to_s.strip
    @fco = "" if @fco.downcase.start_with?("all")
    # A selected FCO can arrive as a name ("FCO-C Sausar") or an id. Resolve
    # through the directory so a later-added office is recognised too.
    @fco = DashboardFcoDirectory.id_for(@fco) || @fco unless @fco.match?(/\A\d+\z/)
  end

  def summary
    @summary ||= calculate_summary
  end

  def rows
    @rows ||= calculate_rows
  end

  def caption
    "#{all_months? ? 'All Months' : @month} · #{DashboardFcoDirectory.name_by_id.fetch(@fco, @fco.presence || 'All FCOs')}"
  end

  private

  def cc_name_value(value)
    name = value.to_s.strip
    return nil if name.empty? || name.match?(CC_NAME_NONE)

    name
  end

  def all_months?
    @month.blank? || @month.downcase.start_with?("all")
  end

  def calculate_rows
    target_data      = fetch_cc_targets
    achievement_data = fetch_cc_achievements
    jj_data          = fetch_cc_jj_names

    # Only show CCs that have been given a cc_target > 0
    results = target_data.keys.map do |key|
      fco_id, cc_name = key
      target      = target_data[key].to_i
      achievement = achievement_data[key].to_i
      jj_names    = jj_data[key] || []

      status = if target.positive? && achievement.zero?
        "Red"
      elsif target.positive? && achievement > 0 && achievement < target
        "Yellow"
      else
        "Green"
      end

      fpo_name = DashboardFcoDirectory.name_by_id[fco_id].presence || @fco_names[fco_id].presence || fco_id

      {
        "month"            => all_months? ? "All Months" : @month,
        "fco_id"           => fco_id,
        "fpo_name"         => fpo_name,
        "cluster_incharge" => cc_name,
        "jj_names"         => jj_names,
        "target"           => target,
        "achievement"      => achievement,
        "status"           => status
      }
    end

    results.select { |row| DashboardFcoDirectory.ids.include?(row["fco_id"].to_s) }
      .select { |row| @fco.blank? || row["fco_id"] == @fco }
      .sort_by { |row| [row["fco_id"].to_s, row["cluster_incharge"].to_s] }
  end

  def calculate_summary
    detailed_rows = rows
    by_fco_and_status = detailed_rows.group_by { |r| [r["fco_id"], r["status"]] }

    selected_fcos = @fco.blank? ? detailed_rows.map { |row| row["fco_id"] }.uniq : [@fco]
    summary_results = []

    selected_fcos.each do |fco_id|
      %w[Red Yellow Green].each do |status|
        cc_rows = by_fco_and_status[[fco_id, status]] || []
        summary_results << {
          "month"             => all_months? ? "All Months" : @month,
          "fco_id"            => fco_id,
          "status"            => status,
          "cc_count"          => cc_rows.size,
          "total_target"      => cc_rows.sum { |r| r["target"] },
          "total_achievement" => cc_rows.sum { |r| r["achievement"] }
        }
      end
    end

    summary_results
  end

  def fetch_cc_targets
    targets = {}
    return targets unless ActiveRecord::Base.connection.table_exists?("target_mappings")

    target_scope = @calculator.send(:dashboard_visible_target_scope).joins("LEFT JOIN vrps ON target_mappings.vrp_id = vrps.id")
    unless all_months?
      target_scope = target_scope.where("LOWER(TRIM(target_mappings.month_name)) = ?", @month.downcase)
    end

    target_scope.pluck(
      "target_mappings.id",
      "target_mappings.cc_target",
      "target_mappings.fco_id",
      "target_mappings.fco_name",
      "vrps.fcoc",
      "vrps.cluster_incharge"
    ).each do |_id, cc_target, fco_id_raw, fco_name_raw, fcoc_raw, cluster_incharge|
      cc_val = cc_target.to_i
      next if cc_val <= 0

      fco_id  = normalize_fco_id(fco_id_raw, fco_name_raw, fcoc_raw)
      next unless DashboardFcoDirectory.ids.include?(fco_id.to_s)
      next if @fco.present? && fco_id.to_s != @fco

      @fco_names[fco_id] = fco_name_raw.to_s.strip.presence || fcoc_raw.to_s.strip
      cc_name = cluster_incharge.to_s.strip
      next if cc_name.blank?

      key = [fco_id, cc_name]
      targets[key] = (targets[key] || 0) + cc_val
    end

    targets
  end

  # Count unique training records (achievements) per [fco_id, cc_name].
  def fetch_cc_achievements(target_keys = nil)
    target_keys ||= fetch_cc_targets.keys
    achievements = {}
    return achievements unless ActiveRecord::Base.connection.table_exists?("module_records")

    cc_to_target_fco = {}
    target_keys.each do |fco_id, cc_name|
      cc_to_target_fco[cc_name.to_s.strip.downcase] = fco_id
    end

    valid_jj_cc_map = {}
    if ActiveRecord::Base.connection.table_exists?("target_mappings")
      scope = @calculator.send(:dashboard_visible_target_scope).joins("LEFT JOIN vrps ON target_mappings.vrp_id = vrps.id")
        .where("target_mappings.cc_target > 0")
      scope = scope.where("LOWER(TRIM(target_mappings.month_name)) = ?", @month.downcase) unless all_months?

      scope.pluck(
        "vrps.id",
        "vrps.name",
        "target_mappings.fco_id",
        "target_mappings.fco_name",
        "vrps.fcoc",
        "vrps.cluster_incharge"
      ).each do |vrp_id, vrp_name, fco_id_raw, fco_name_raw, fcoc_raw, cluster_incharge|
        fco_id = normalize_fco_id(fco_id_raw, fco_name_raw, fcoc_raw)
        cc_name = cluster_incharge.to_s.strip
        next if cc_name.blank?

        pair = [fco_id, cc_name]
        valid_jj_cc_map[vrp_name.to_s.strip.downcase] = pair if vrp_name.present?
        valid_jj_cc_map[vrp_id.to_s] = pair if vrp_id.present?
      end
    end

    vrp_cc_map = {}
    if ActiveRecord::Base.connection.table_exists?("vrps")
      Vrp.where(id: @calculator.send(:dashboard_visible_vrp_ids)).where.not(cluster_incharge: [nil, ""]).each do |v|
        cc_name = v.cluster_incharge.to_s.strip
        fco_id = cc_to_target_fco[cc_name.downcase] || normalize_fco_id(v.fcoc)
        pair = [fco_id, cc_name]
        vrp_cc_map[v.id.to_s] = pair
        vrp_cc_map[v.name.to_s.strip.downcase] = pair if v.name.present?
      end
    end

    records = @calculator.send(:dashboard_training_participation_records, month_name: all_months? ? nil : @month)
    records.each do |rec|
      data = rec.data || {}
      rec_month = data["month"].to_s.strip
      next if !all_months? && rec_month.downcase != @month.downcase

      # An explicit current field wins over stale legacy aliases, including
      # blank/N/A. Only records without that field may use a legacy value.
      selected_key = CC_NAME_KEYS.find { |key_name| data.key?(key_name) }
      cc_name = cc_name_value(data[selected_key]) if selected_key

      # A Cluster Coordinator cleared -- or set to "N/A" -- on the training form
      # must stop counting towards that CC. The JJ/VRP fallback below is only for
      # legacy records saved before this field existed, where the key is absent
      # altogether; otherwise removing the name would keep the old achievement.
      next if cc_name.blank? && CC_NAME_KEYS.any? { |key_name| data.key?(key_name) }

      key = nil
      if cc_name.present?
        target_fco = cc_to_target_fco[cc_name.downcase] || normalize_fco_id(data["ics_block"], data["fco_name"], data["fcoc"])
        key = [target_fco, cc_name]
      end

      if key.blank? || !target_keys.include?(key)
        created_by_id = data["created_by_id"].to_s.strip
        trainer_name  = data["trainer_name"].to_s.strip.downcase
        vrp_name      = data["select_vrp"].to_s.strip.downcase.presence || data["jeevika_jankar_name"].to_s.strip.downcase.presence

        matched = valid_jj_cc_map[created_by_id] ||
                  valid_jj_cc_map[trainer_name] ||
                  valid_jj_cc_map[vrp_name] ||
                  vrp_cc_map[created_by_id] ||
                  vrp_cc_map[trainer_name] ||
                  vrp_cc_map[vrp_name]

        if matched
          fco_id, cc = matched
          target_fco = cc_to_target_fco[cc.downcase] || fco_id
          key = [target_fco, cc]
        end
      end

      if key.present? && !target_keys.include?(key)
        matched_cc_key = target_keys.find { |_fco, cc| cc.casecmp(key[1]).zero? }
        key = matched_cc_key if matched_cc_key
      end

      next if key.blank?

      achievements[key] = (achievements[key] || 0) + 1
    end

    achievements
  end

  # Fetch JJ names grouped per [fco_id, cc_name] from target_mappings
  def fetch_cc_jj_names
    jj_names = {}
    return jj_names unless ActiveRecord::Base.connection.table_exists?("target_mappings")

    scope = @calculator.send(:dashboard_visible_target_scope).joins("LEFT JOIN vrps ON target_mappings.vrp_id = vrps.id")
      .where("target_mappings.cc_target > 0")
    unless all_months?
      scope = scope.where("LOWER(TRIM(target_mappings.month_name)) = ?", @month.downcase)
    end

    scope.pluck(
      "vrps.name",
      "target_mappings.fco_id",
      "target_mappings.fco_name",
      "vrps.fcoc",
      "vrps.cluster_incharge"
    ).each do |vrp_name, fco_id_raw, fco_name_raw, fcoc_raw, cluster_incharge|
      fco_id  = normalize_fco_id(fco_id_raw, fco_name_raw, fcoc_raw)
      cc_name = cluster_incharge.to_s.strip
      next if cc_name.blank?

      key = [fco_id, cc_name]
      jj_names[key] ||= []
      jj_names[key] << vrp_name.to_s.strip if vrp_name.present?
      jj_names[key].uniq!
    end

    jj_names
  end

  def normalize_fco_id(*vals)
    explicit_id = vals.first.to_s.strip.split("||").first.to_s
    return explicit_id if explicit_id.match?(/\A\d+\z/)

    combined = vals.compact.map(&:to_s).join(" ").strip.downcase
    DashboardFcoDirectory.id_by_name.each do |name, id|
      return id if combined.include?(name) || combined.include?(id.downcase)
    end

    vals.map { |value| value.to_s.strip.split("||").first.to_s }.find { |value| value.match?(/\A\d+\z/) } ||
      vals.map { |value| value.to_s.strip }.find(&:present?).to_s
  end
end
