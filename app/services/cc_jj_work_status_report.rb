class CcJjWorkStatusReport
  HEADERS = ["month", "fco_id", "fpo_id", "fpo_name", "cluster_incharge", "vrp_name", "total_farmer", "No Activity Mapping", "No Training Mapping", "Training Mapped But No Entry", "Training Entry Done", "Red", "Completed", "Cluster Coordinator Involved", "Agronomist Involved"].freeze

  def initialize(calculator:, month: nil, fco: nil)
    @calculator = calculator
    filters = calculator.request ? calculator.params : {}
    @month = (month || (filters.key?(:month) ? filters[:month] : Date.current.prev_month.strftime("%B"))).to_s.strip
    @fco = (fco || filters[:fcoc] || filters[:fco] || filters[:fco_id]).to_s.strip
    @fco = "" if @fco.downcase.start_with?("all")
    @fco = fco_id_for(@fco)
  end

  def summary
    @summary ||= begin
      result = execute("summary")
      represented = result.map { |row| row["fco_id"] }
      rows.map { |row| row["fco_id"] }.uniq.each do |fco_id|
        next if represented.include?(fco_id)

        result << { "month" => all_months? ? "All Months" : @month, "fco_id" => fco_id,
          "status" => "No Training Mapping", "toatl_cc" => 0, "toatl_jj" => 0,
          "map_farmer" => 0, "red_farmer" => 0, "green_farmer" => 0 }
      end
      result.sort_by { |row| [row["fco_id"].to_s, row["status"] == "Red" ? 0 : 1] }
    end
  end

  def rows
    @rows ||= execute("rows")
  end

  def caption
    label = @fco.present? ? (fco_id_names[@fco.to_s].presence || @fco) : "All FCO"
    "#{all_months? ? 'All Months' : @month} · #{label}"
  end

  private

  # An FCO may arrive as its id or its name; map it onto the id using whatever
  # AFL holds, rather than knowing about two particular FCOs.
  def fco_id_for(value)
    return value if value.blank? || value.to_s.match?(/\A\d+\z/)

    needle = value.to_s.strip.downcase
    match = fco_id_names.find { |_id, name| name.present? && needle.include?(name.to_s.downcase) }
    match ? match.first.to_s : value
  end

  def fco_id_names
    return @fco_id_names if defined?(@fco_id_names)

    @fco_id_names = if defined?(Afl) && Afl.table_exists?
      Afl.where.not(fco_id: [nil, ""]).distinct.pluck(:fco_id, :fco).each_with_object({}) do |(id, name), memo|
        key = id.to_s.strip
        memo[key] = name.presence if key.present? && memo[key].blank?
      end
    else
      {}
    end
  end

  def all_months?
    @month.blank? || @month.downcase.start_with?("all")
  end

  def execute(kind)
    sql = Rails.root.join("app/queries/cc_jj_work_status", "#{kind}.sql").read
    connection = ActiveRecord::Base.connection
    selected_fcos = @fco.present? ? [@fco] : []
    fcos = selected_fcos.map { |id| connection.quote(id) }.join(", ")
    assignment_scope = if @calculator.send(:dashboard_global_view_user?)
      "TRUE"
    else
      ids = @calculator.send(:dashboard_visible_vrp_ids).map { |id| connection.quote(id) }
      ids.empty? ? "FALSE" : "m.vrp_id IN (#{ids.join(', ')})"
    end
    replacements = {
      assignment_visibility_filter: assignment_scope,
      summary_fco_filter: selected_fcos.empty? ? "TRUE" : "LOWER(TRIM(fvm.fco_id)) IN (#{fcos})",
      list_fco_filter: selected_fcos.empty? ? "TRUE" : "LOWER(TRIM(a.fco_id)) IN (#{fcos})",
      month_label: connection.quote(all_months? ? "All Months" : @month),
      target_month_filter: all_months? ? "TRUE" : "LOWER(TRIM(t.month_name)) = #{connection.quote(@month.downcase)}",
      entry_month_filter: all_months? ? "TRUE" : "LOWER(TRIM(COALESCE(mr.data::jsonb ->> 'month', ''))) = #{connection.quote(@month.downcase)}"
    }
    sql = sql.gsub(/%\{(\w+)\}/) { replacements.fetch(Regexp.last_match(1).to_sym) }
    sql = @calculator.send(:dashboard_scoped_training_sql, sql)
    connection.select_all(sql).to_a.map do |row|
      if kind == "rows"
        row["vrp_name"] = row["vrp_name"].presence || "Not mapped"
        row["cluster_incharge"] = row["cluster_incharge"].presence || "Not assigned"
      end
      row
    end
  end
end
