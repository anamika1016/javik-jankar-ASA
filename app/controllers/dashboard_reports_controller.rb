class DashboardReportsController < ModulesController
  # Dashboard reports ported from VRP; entry screens keep ModulesController.
  prepend_view_path Rails.root.join("app/views/modules")

  def cc_target_status_list
    @cc_target_status_report = CcTargetStatusReport.new(calculator: self)
    @cc_target_rows = dashboard_search_rows(@cc_target_status_report.rows)
    respond_to do |format|
      format.html { render :cc_target_status_list }
      format.xlsx do
        headers = ["month", "fco_id", "fpo_name", "cluster_incharge", "jj_names", "target", "achievement", "status"]
        rows = @cc_target_rows.map { |row| [row["month"], row["fco_id"], row["fpo_name"], row["cluster_incharge"], Array(row["jj_names"]).join(", "), row["target"], row["achievement"], row["status"]] }
        send_xlsx(headers: headers, rows: rows, filename: "cc-target-status.xlsx", sheet_name: "CC Target Status")
      end
    end
  end

  def dashboard
    if vrp_login_user?
      prepare_vrp_dashboard
      return
    end

    # 1. Load unfiltered VRPs and Targets in the user's visible scope first
    unfiltered_vrps = dashboard_vrps
    unfiltered_targets = dashboard_target_mappings

    # Start with all targets and VRPs in user scope
    t_scope = unfiltered_targets.to_a
    v_scope = unfiltered_vrps.to_a

    # Apply search filter (if search query is present)
    search_query = dashboard_filter_param(:search)
    if search_query.present?
      q = search_query.to_s.downcase.strip
      v_scope = v_scope.select do |v|
        v.name.to_s.downcase.include?(q) ||
          v.mobile_no.to_s.include?(q) ||
          v.role.to_s.downcase.include?(q) ||
          v.fcoc.to_s.downcase.include?(q) ||
          v.cluster_incharge.to_s.downcase.include?(q)
      end
      t_scope = t_scope.select do |t|
        t.vrp&.name.to_s.downcase.include?(q) ||
          t.month_name.to_s.downcase.include?(q) ||
          t.village_name.to_s.downcase.include?(q) ||
          t.main_activity_name.to_s.downcase.include?(q) ||
          t.activity_name.to_s.downcase.include?(q)
      end
    end

    # ─── CASCADING FILTER DROPDOWNS ───
    # 1. Activity Filter (always show all in initial scope, restrict others)
    @filter_main_activity_options = t_scope.map(&:main_activity_name).uniq.compact_blank.sort
    # Open the dashboard on the farmer-training view when it is available;
    # an explicitly selected activity always takes precedence.
    @dashboard_main_activity_filter_value = dashboard_filter_param(:main_activity)
    unless params.key?(:main_activity)
      @dashboard_main_activity_filter_value ||= @filter_main_activity_options.find do |activity|
        normalize_dashboard_text(activity) == normalize_dashboard_text("Farmer Activity") ||
          normalize_dashboard_text(activity) == normalize_dashboard_text("Farmers' Training") ||
          normalize_dashboard_text(activity) == normalize_dashboard_text("Farmers Training")
      end
    end
    normalized_dashboard_main_activity = normalize_dashboard_text(@dashboard_main_activity_filter_value)
    @dashboard_farmer_activity_mode = @dashboard_main_activity_filter_value.blank? || [
      "Farmer Activity",
      "Farmers' Training",
      "Farmers Training"
    ].any? { |value| normalized_dashboard_main_activity == normalize_dashboard_text(value) } ||
      normalized_dashboard_main_activity.include?(normalize_dashboard_text("Training"))
    selected_main_activity = @dashboard_main_activity_filter_value
    selected_sub_activity = dashboard_filter_param(:sub_activity)
    legacy_activity = dashboard_filter_param(:activity)
    if selected_main_activity.present?
      normalized_selected_main_activity = normalize_dashboard_text(selected_main_activity)
      main_activity_matches = t_scope.select { |t| normalize_dashboard_text(t.main_activity_name) == normalized_selected_main_activity }
      t_scope = main_activity_matches
    elsif legacy_activity.present?
      t_scope = t_scope.select { |t| t.main_activity_name == legacy_activity || t.activity_name == legacy_activity }
    end
    @filter_sub_activity_options = dashboard_filter_sub_activity_options(t_scope)
    selected_sub_activity = nil unless @filter_sub_activity_options.any? { |value| normalize_dashboard_text(value) == normalize_dashboard_text(selected_sub_activity) }
    if selected_sub_activity.nil?
      params.delete(:sub_activity)
      @dashboard_filter_param_cache = {}
    end

    if selected_sub_activity.present?
      t_scope = t_scope.select { |t| normalize_dashboard_text(t.activity_name) == normalize_dashboard_text(selected_sub_activity) }
    end
    if selected_main_activity.present? || selected_sub_activity.present? || legacy_activity.present?
      v_ids = t_scope.map(&:vrp_id).uniq.to_set
      v_scope = v_scope.select { |v| v_ids.include?(v.id) }
    end

    # 2. FCO Filter (depends on selected Activity)
    vrp_fcos = unfiltered_vrps.map(&:fcoc)
    target_fcos = unfiltered_targets.map(&:fco_name)
    afl_fcos = ModuleRecord.where(module_slug: "add-farmer-form").pluck(Arel.sql("data::jsonb ->> 'fco_name'"))
    all_fcos = (DashboardFcoDirectory.names + vrp_fcos + target_fcos + afl_fcos).compact_blank.map { |f| f.to_s.strip }.reject(&:blank?)
    @filter_fcoc_options = all_fcos.group_by { |f| AgreementVrpScope.office_key(f) }.filter_map { |key, names| DashboardFcoDirectory.name_for(names.first) if key.present? }.uniq.sort
    # A posted user only works in their own FCO, so the picker offers just that
    # one and comes pre-selected. Admin keeps the full list.
    unless dashboard_global_view_user?
      own_office_keys = dashboard_current_user_office_keys
      if own_office_keys.any?
        own_options = @filter_fcoc_options.select do |name|
          own_office_keys.include?(AgreementVrpScope.office_key(name))
        end
        # Their posting is authoritative: show it even when no Jeevika Jankar or
        # target carries that office yet, otherwise the picker comes up empty.
        own_options = dashboard_current_user_office_names if own_options.blank?
        @filter_fcoc_options = own_options if own_options.any?
      end
    end
    default_visible_fcoc = dashboard_default_visible_fcoc(@filter_fcoc_options)
    @dashboard_fcoc_filter_value = dashboard_filter_param(:fcoc) || default_visible_fcoc
    if @dashboard_fcoc_filter_value.present?
      f = normalize_dashboard_text(@dashboard_fcoc_filter_value)
      v_scope = v_scope.select { |v| training_fcoc_text_matches?(v.fcoc, @dashboard_fcoc_filter_value) }
      v_ids = v_scope.map(&:id).to_set
      t_scope = t_scope.select { |t| t.vrp_id.present? && v_ids.include?(t.vrp_id) }
    else
      default_fco_values = dashboard_summary_fco_filter_values
      v_scope = v_scope.select { |v| default_fco_values.blank? || (training_fcoc_filter_values(v.fcoc) & default_fco_values).any? }
      t_scope = t_scope.select do |t|
        target_values = training_fcoc_filter_values(t.fco_name, t.fco_id, t.vrp&.fcoc)
        default_fco_values.blank? || (target_values & default_fco_values).any?
      end
    end

    # 3. Cluster Incharge Filter (depends on selected Activity & FCO)
    current_cluster_labels = hierarchy_cluster_incharge_labels
    @filter_cluster_incharge_options = v_scope.filter_map do |vrp|
      saved_label = vrp.cluster_incharge.to_s.strip
      next if saved_label.blank?

      canonical_label = current_cluster_labels.find { |label| cluster_label_matches?(label, saved_label) }
      (canonical_label.presence || saved_label).sub(/\s*\([^)]*\)\s*\z/, "").strip
    end.uniq { |label| normalize_dashboard_text(label) }.sort
    selected_cluster_incharge = dashboard_filter_param(:cluster_incharge)
    if selected_cluster_incharge.present?
      ci = selected_cluster_incharge.to_s
      v_scope = v_scope.select { |v| cluster_label_matches?(ci, v.cluster_incharge) }
      v_ids = v_scope.map(&:id).to_set
      t_scope = t_scope.select { |t| t.vrp_id.present? && v_ids.include?(t.vrp_id) }
    end

    # 4. ICS Filter
    ics_farmers = dashboard_visible_farmer_scope
    if @dashboard_fcoc_filter_value.present?
      ics_farmers = ics_farmers.where(fco_id: training_fcoc_ids_from_param(@dashboard_fcoc_filter_value))
    end
    @filter_ics_options = (t_scope.map { |t| t.ics_name.presence || t.ics_id } +
      ics_farmers.distinct.pluck(Arel.sql("COALESCE(NULLIF(TRIM(ics_name), ''), ics_id)"))).uniq.compact_blank.sort
    selected_ics_filter = dashboard_filter_param(:ics)
    if selected_ics_filter.present?
      selected_ics = selected_ics_filter.to_s
      t_scope = t_scope.select { |t| (t.ics_name.presence || t.ics_id).to_s == selected_ics }
      v_ids = t_scope.map(&:vrp_id).uniq.to_set
      v_scope = v_scope.select { |v| v_ids.include?(v.id) }
    end

    # 5. Month Filter (depends on Activity, FCO, Cluster Incharge, ICS)
    @filter_month_options = (t_scope.map(&:month_name) + month_master_month_options)
      .uniq
      .compact_blank
      .sort_by { |m| dashboard_month_index(m) || 0 }
    weekly_target_scope = t_scope.dup
    # Monthly dashboard summary opens on the current month by default. Users
    # can still choose All Months or another month from the filter.
    default_dashboard_month = DashboardDefaults.month
    @dashboard_month_filter_value = params.key?(:month) ? dashboard_filter_param(:month) : default_dashboard_month
    if @dashboard_month_filter_value.present?
      m = normalize_dashboard_text(@dashboard_month_filter_value)
      t_scope = t_scope.select { |t| normalize_dashboard_text(t.month_name) == m }
      v_ids = t_scope.map(&:vrp_id).uniq.to_set
      v_scope = v_scope.select { |v| v_ids.include?(v.id) }
    end

    # 6. Post Filter (depends on all above)
    @filter_post_options = v_scope.map(&:role).uniq.compact_blank.sort
    selected_post_filter = dashboard_filter_param(:post)
    if selected_post_filter.present?
      p_filter = selected_post_filter.to_s
      v_scope = v_scope.select { |v| v.role == p_filter }
      v_ids = v_scope.map(&:id).to_set
      t_scope = t_scope.select { |t| t.vrp_id.present? && v_ids.include?(t.vrp_id) }
    end

    # 7. VRP Name Filter (depends on all above)
    @filter_vrp_options = v_scope.map { |v| [v.name, v.id] }.uniq.sort_by(&:first)
    selected_vrp_filter = dashboard_filter_param(:vrp_id)
    if selected_vrp_filter.present?
      vid = selected_vrp_filter.to_i
      v_scope = v_scope.select { |v| v.id == vid }
      t_scope = t_scope.select { |t| t.vrp_id == vid }
    end

    @filtered_vrps = v_scope
    @filtered_targets = t_scope
    if params[:demonstration_list] == "true"
      @demonstration_method_report = DashboardDemonstrationMethodReport.new(targets: t_scope, month: @dashboard_month_filter_value, cache: dashboard_sql_cache)
      @demonstration_method_rows = dashboard_search_rows(@demonstration_method_report.rows)
      respond_to do |format|
        format.html { render :demonstration_method_list }
        format.json { render json: { success: true, records: @demonstration_method_rows, count: @demonstration_method_rows.size } }
        format.xlsx do
          send_xlsx(headers: DashboardDemonstrationMethodReport::EXPORT_HEADERS,
            rows: @demonstration_method_rows.map { |row| DashboardDemonstrationMethodReport::EXPORT_HEADERS.map { |key| row[key] } },
            filename: "demonstration-method.xlsx", sheet_name: "Demonstration Method")
        end
      end
      return
    end
    # View List behind the "Main Major Work Indicator - Other" box: the saved
    # Other Target entries the box totals, for the same month and FCO.
    if params[:other_indicator_list] == "true"
      @other_indicator_rows = dashboard_other_target_entry_rows
      # Month dropdown comes from the Month Master, with any month that already
      # has entries added so a saved record is never unreachable.
      @other_indicator_month_options = (
        month_master_month_options + @other_indicator_rows.filter_map { |row| row["month"].presence }
      ).uniq { |month| normalize_dashboard_text(month) }.sort_by { |month| [dashboard_month_index(month) || 99, month] }
      respond_to do |format|
        format.html { render :other_indicator_list }
        format.json { render json: { success: true, records: @other_indicator_rows, count: @other_indicator_rows.size } }
        format.xlsx do
          send_xlsx(headers: OTHER_INDICATOR_LIST_HEADERS.keys,
            rows: @other_indicator_rows.map { |row| OTHER_INDICATOR_LIST_HEADERS.values.map { |key| row[key] } },
            filename: "main-major-work-indicator-other.xlsx", sheet_name: "Other Indicator")
        end
      end
      return
    end
    @dashboard_fco_names = DashboardFcoDirectory.name_by_id
    @cc_jj_work_status_report = DashboardCcJjWorkStatusReport.new(calculator: self)
    @cc_target_status_report = CcTargetStatusReport.new(calculator: self)
    if params[:work_status_list] == "true"
      @work_status_rows = dashboard_search_rows(@cc_jj_work_status_report.rows)
      if %w[Red Completed].include?(params[:work_status])
        @work_status_rows.select! { |row| row[params[:work_status]].to_i.positive? }
      end
      respond_to do |format|
        format.html { render :cc_jj_work_status_list }
        format.json { render json: { success: true, records: @work_status_rows, count: @work_status_rows.size } }
        format.xlsx do
          send_xlsx(headers: DashboardCcJjWorkStatusReport::HEADERS,
            rows: @work_status_rows.map { |row| DashboardCcJjWorkStatusReport::HEADERS.map { |key| row[key] } },
            filename: "cc-jj-work-status.xlsx", sheet_name: "CC and JJ Work Status")
        end
      end
      return
    end
    preload_dashboard_vrp_identity_records!(@filtered_vrps)

    # ─── BILL FILTERING ───
    filtered_vrp_ids = @filtered_vrps.map { |v| v.id.to_s }
    dashboard_filters_active = [
      dashboard_filter_param(:search), dashboard_filter_param(:activity), dashboard_filter_param(:main_activity),
      dashboard_filter_param(:sub_activity), dashboard_filter_param(:fcoc), dashboard_filter_param(:cluster_incharge),
      dashboard_filter_param(:ics), dashboard_filter_param(:month), dashboard_filter_param(:post), dashboard_filter_param(:vrp_id)
    ].any?(&:present?) || [
      @dashboard_main_activity_filter_value, selected_sub_activity, @dashboard_fcoc_filter_value,
      selected_cluster_incharge, selected_ics_filter, @dashboard_month_filter_value, selected_post_filter, selected_vrp_filter
    ].any?(&:present?)

    bill_scope = ModuleRecord.where(module_slug: "jeevika-jankar-bill-process")
    if dashboard_filters_active || module_cluster_incharge_login?
      bill_scope = filtered_vrp_ids.any? ? bill_scope.where("data::jsonb ->> 'select_vrp' IN (?)", filtered_vrp_ids) : ModuleRecord.none
    end
    bill_records = dashboard_sql_cache.select_all(bill_summary_scope(bill_scope).to_sql)
      .map { |row| ModuleRecord.instantiate(row) }
    unless admin_dashboard_user?
      bill_records = bill_records.select { |r| jeevika_jankar_bill_record_visible?(r) }
    end
    bill_records = bill_records.select { |r| jeevika_jankar_bill_blocks_duplicate?(r) }

    # A cluster incharge dashboard is a roll-up of the VRPs mapped below that
    # incharge. Approval visibility can legitimately include unrelated bills,
    # but those records must not leak into the cluster dashboard totals.
    if module_cluster_incharge_login?
      bill_records = bill_records.select do |record|
        bill_vrp = jeevika_bill_vrp(record)
        bill_vrp.present? && filtered_vrp_ids.include?(bill_vrp.id.to_s)
      end
    end

    bill_records = bill_records.select do |r|
      next false unless r.data.present?

      # Keep bills mapped to currently visible/filtered VRPs.
      next true if filtered_vrp_ids.include?(r.data["select_vrp"].to_s)

      # Approver/creator bills must still count even when VRP is outside dashboard VRP scope.
      next true unless dashboard_filters_active

      false
    end

    # Restrict bills by Selected Activity
    selected_bill_activity = dashboard_filter_param(:activity)
    selected_bill_main_activity = dashboard_filter_param(:main_activity)
    selected_bill_sub_activity = dashboard_filter_param(:sub_activity)
    if selected_bill_activity.present? || selected_bill_main_activity.present? || selected_bill_sub_activity.present?
      act = selected_bill_activity.to_s
      main_activity = selected_bill_main_activity.to_s
      sub_activity = selected_bill_sub_activity.to_s
      bill_records = bill_records.select do |r|
        items = jeevika_bill_detail_rows(r)
        items.any? do |item|
          legacy_matches = act.blank? || item["main_activity"] == act || item["activity"] == act
          main_matches = main_activity.blank? || normalize_dashboard_text(item["main_activity"]) == normalize_dashboard_text(main_activity)
          sub_matches = sub_activity.blank? || normalize_dashboard_text(item["activity"]) == normalize_dashboard_text(sub_activity)
          legacy_matches && main_matches && sub_matches
        end
      end
    end

    @filtered_bills = bill_records

    targets = @filtered_targets
    @training_month_options = dashboard_month_options_for_targets(targets)
    selected_month = dashboard_selected_training_month_name.presence || @dashboard_month_filter_value.presence || default_vrp_dashboard_month(@training_month_options, targets)
    month_targets = dashboard_targets_for_month(targets, selected_month)
    @training_sub_activity_options = dashboard_sub_activity_options_for_targets(month_targets, selected_month)
    requested_sub_activity = dashboard_selected_training_sub_activity_name
    selected_sub_activity = @training_sub_activity_options.find do |option|
      normalize_dashboard_text(option) == normalize_dashboard_text(requested_sub_activity)
    end || @training_sub_activity_options.first
    @dashboard_title = admin_dashboard_user? ? "Admin Dashboard" : dashboard_current_user_title
    @dashboard_caption = admin_dashboard_user? ? "Live complete system summary." : "Live summary for your mapped records."
    @training_selected_month = selected_month
    @training_selected_sub_activity = selected_sub_activity
    default_status_month = default_vrp_dashboard_month(@training_month_options, targets)
    # The top "Month" filter's "All Months" option submits month="" -- previously
    # that blank value fell straight through to default_status_month below, so
    # picking "All Months" had no effect here and silently showed one month's
    # numbers. When the user has actually submitted the filter with "All Months"
    # selected (the :month param key is present but blank), honor it as "all" so
    # the Farmer Training Participation Status (red/yellow/green) boxes use the
    # all-months query. Any other case (no :month param at all, or a specific
    # month chosen) is unchanged.
    @participation_month_filter_value = if params.key?(:month) && @dashboard_month_filter_value.blank?
      "all"
    else
      @dashboard_month_filter_value.presence || default_status_month
    end
    @participation_selected_month = @participation_month_filter_value == "all" ? nil : @participation_month_filter_value
    @participation_fcoc_filter_value = @dashboard_fcoc_filter_value.presence || dashboard_default_visible_fcoc(@filter_fcoc_options)
    @participation_week_filter_value = dashboard_filter_param(:weekly_target_week).to_i if dashboard_filter_param(:weekly_target_week).present?
    @participation_week_filter_value = nil unless (1..4).include?(@participation_week_filter_value)
    if @dashboard_farmer_activity_mode
      participation_dashboard_counts = cached_training_participation_dashboard_counts(
        month_name: @participation_selected_month,
        fcoc_name: @participation_fcoc_filter_value,
        week_number: @participation_week_filter_value
      )
      mapped_count, mapped_popups = farmer_training_mapped_farmer_count_and_popups(
        month_name: @participation_selected_month,
        fcoc_name: @participation_fcoc_filter_value
      )
      no_training_count, no_training_popups, red_fco_details = farmer_training_no_training_count_and_popups(
        month_name: @participation_selected_month,
        fcoc_name: @participation_fcoc_filter_value
      )
      yellow_count, yellow_popups = farmer_training_yellow_farmer_count_and_popups(
        month_name: @participation_selected_month,
        fcoc_name: @participation_fcoc_filter_value
      )
      green_count, green_popups = farmer_training_green_farmer_count_and_popups(
        month_name: @participation_selected_month,
        fcoc_name: @participation_fcoc_filter_value
      )
      participation_dashboard_counts[:red] = no_training_count if participation_dashboard_counts.is_a?(Hash)
      participation_dashboard_counts[:yellow] = yellow_count if participation_dashboard_counts.is_a?(Hash)
      participation_dashboard_counts[:green] = green_count if participation_dashboard_counts.is_a?(Hash)
      participation_dashboard_counts[:total] = mapped_count if participation_dashboard_counts.is_a?(Hash)

      @training_participation_status_cards = training_participation_dashboard_status_cards(
        participation_dashboard_counts,
        month_name: @participation_selected_month,
        fcoc_name: @participation_fcoc_filter_value,
        week_number: @participation_week_filter_value
      )
      @training_registered_farmer_count = participation_dashboard_counts[:registered_farmer_total].to_i
      @training_unique_farmer_count = mapped_count
      @training_mapped_farmer_count = mapped_count
      @training_mapped_farmer_popups = mapped_popups
      @training_no_training_popups = no_training_popups
      @training_red_fco_details = red_fco_details
      @training_yellow_farmer_popups = yellow_popups
      @training_green_farmer_popups = green_popups
      @training_total_training_farmer_count = participation_dashboard_counts[:target_map_total].to_i
      @training_completed_target_map_count = participation_dashboard_counts[:completed_target_map_total].to_i
      visible_vrp_ids = @filtered_vrps.map(&:id)
      ics_mappings = model_ready?(:VrpIcsMapping) ? VrpIcsMapping.where(vrp_id: visible_vrp_ids).to_a : []
      if selected_ics_filter.present?
        selected_ics = normalize_dashboard_text(selected_ics_filter)
        ics_mappings.select! do |mapping|
          normalize_dashboard_text(mapping.ics_name.presence || mapping.ics_id) == selected_ics
        end
      end
      # Full target/participation rows are available on their dedicated report
      # pages. The dashboard renders summary boxes only, so building those large
      # unused datasets here needlessly multiplies queries and memory usage.
      @ics_farmer_report_month_value = @participation_month_filter_value
      @ics_farmer_report_selected_month = @ics_farmer_report_month_value == "all" ? nil : @ics_farmer_report_month_value
      ics_report_targets = training_participation_targets_for_dashboard(
        month_name: @ics_farmer_report_selected_month,
        fcoc_name: @participation_fcoc_filter_value
      )
      @ics_farmer_report_options = ics_farmer_report_options([], ics_report_targets)
      @ics_farmer_report_selected_ics = dashboard_filter_param(:ics_report_ics)
      @ics_farmer_report_summary = ics_farmer_report_summary([], selected_ics: @ics_farmer_report_selected_ics)
      @weekly_target_month_filter_value = @dashboard_month_filter_value.presence || (params.key?(:month) ? "all" : default_status_month)
      @weekly_dashboard_selected_month = @weekly_target_month_filter_value == "all" ? nil : @weekly_target_month_filter_value
      @weekly_target_fcoc_filter_value = @dashboard_fcoc_filter_value.presence || dashboard_default_visible_fcoc(@filter_fcoc_options)
      @weekly_target_week_filter_value = @participation_week_filter_value
      weekly_dashboard_targets = dashboard_targets_for_month(weekly_target_scope, @weekly_dashboard_selected_month)
      if selected_post_filter.present?
        selected_post = selected_post_filter.to_s
        weekly_dashboard_targets = weekly_dashboard_targets.select { |target| target.vrp&.role.to_s == selected_post }
      end
      if selected_vrp_filter.present?
        selected_vrp_id = selected_vrp_filter.to_s
        weekly_dashboard_targets = weekly_dashboard_targets.select { |target| target.vrp_id.to_s == selected_vrp_id }
      end
      weekly_dashboard_targets = filter_weekly_activity_targets(
        weekly_dashboard_targets,
        activity: dashboard_filter_param(:activity, :main_activity),
        sub_activity: dashboard_filter_param(:training_sub_activity, :sub_activity),
        fcoc: @weekly_target_fcoc_filter_value
      )
      @dashboard_weekly_target_cards = weekly_activity_target_status_cards(
        weekly_dashboard_targets,
        month_name: @weekly_dashboard_selected_month,
        fcoc_name: @weekly_target_fcoc_filter_value,
        week_number: @weekly_target_week_filter_value,
        participation_counts: participation_dashboard_counts
      )
    end
    @dashboard_other_activity_totals ||= dashboard_other_activity_totals(t_scope)
    summary_targets = training_participation_active_vrp_targets(t_scope)
    @dashboard_summary_cards = dashboard_summary_cards(summary_targets)
    @demonstration_method_cards = @dashboard_farmer_activity_mode ? demonstration_method_cards : []
    @dashboard_cards = @dashboard_farmer_activity_mode ? dashboard_cards : []
    @dashboard_generated_at = Time.current

    respond_to do |format|
      format.html
      format.xlsx do
        export_rows = dashboard_filter_export_rows
        send_xlsx(
          headers: export_rows.shift || [],
          rows: export_rows,
          filename: "dashboard-export-#{Time.current.strftime("%Y%m%d%H%M")}.xlsx",
          sheet_name: "Dashboard Export"
        )
      end
    end
  end


  # Drill-down for the Demonstration Method View List "Target Farmer Count" column.
  # Lists the targeted farmers (from target_mappings.afl_ids) for one JJ + month,
  # restricted to the farmers/targets the current user is allowed to see.

  def demonstration_method_farmers
    vrp_id = params[:vrp_id].to_s.strip
    month = params[:training_month].presence || params[:month].presence
    @demonstration_farmer_vrp = model_ready?(:Vrp) ? Vrp.find_by(id: vrp_id) : nil
    @demonstration_farmer_month = month

    base = dashboard_visible_target_scope
    base = base.where(vrp_id: vrp_id) if vrp_id.present?
    base = base.where("LOWER(TRIM(month_name)) = ?", month.to_s.strip.downcase) if month.present?

    farmer_sql = <<~SQL
      SELECT DISTINCT a.id AS "Farmer ID", a.farmer_name AS "Farmer Name",
        a.father_name AS "Father Name", a.tracenet_no AS "TraceNet No",
        CASE WHEN UPPER(BTRIM(COALESCE(a.mobile_no, ''))) IN ('', 'NULL') THEN NULL ELSE a.mobile_no END AS "Mobile No"
      FROM (#{base.select(:afl_ids).to_sql}) t
      CROSS JOIN LATERAL jsonb_array_elements_text(
        CASE WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb ELSE '[]'::jsonb END
      ) AS af(afl_id)
      JOIN afls a ON a.id::text = af.afl_id
      ORDER BY a.farmer_name
    SQL
    @demonstration_farmers = TargetMapping.connection.select_all(farmer_sql).to_a

    respond_to do |format|
      format.html { render :demonstration_method_farmers }
      format.xlsx do
        headers = @demonstration_farmers.first&.keys || ["Farmer ID", "Farmer Name", "Father Name", "TraceNet No", "Mobile No"]
        send_xlsx(headers: headers,
          rows: @demonstration_farmers.map { |r| headers.map { |k| r[k] } },
          filename: "demonstration-method-farmers.xlsx", sheet_name: "Targeted Farmers")
      end
    end
  end

  def farmer_training_participation
    selected_month = dashboard_filter_param(:training_month, :month)
    selected_sub_activity = dashboard_filter_param(:training_sub_activity, :sub_activity)
    selected_fcoc = dashboard_filter_param(:training_fcoc, :fcoc)
    selected_fcoc = Array(params[:fco_id]).reject(&:blank?) if selected_fcoc.blank? && params[:fco_id].present?
    selected_main_activity = dashboard_filter_param(:main_activity, :activity)
    selected_training_method = params[:training_method].to_s.strip
    selected_week_param = params[:week].presence || params[:weekly_target_week].presence
    selected_week = selected_week_param.to_i if selected_week_param.present?
    selected_week = nil unless (1..4).include?(selected_week)
    selected_status = normalize_training_participation_status(params[:status]) || "green"
    training_records = dashboard_training_participation_records(month_name: selected_month, main_activity_name: selected_main_activity, sub_activity_name: selected_sub_activity, fcoc_name: selected_fcoc)
    training_records = training_records.select { |record| training_record_week_number(record) == selected_week } if selected_week.present?
    if selected_training_method.present?
      training_records = training_records.select do |record|
        normalize_dashboard_text(record.data["training_method"]) == normalize_dashboard_text(selected_training_method)
      end
    end
    participation_targets = training_participation_targets_for_dashboard(
      month_name: selected_month,
      fcoc_name: selected_fcoc,
      main_activity_name: selected_main_activity,
      sub_activity_name: selected_sub_activity
    )
    participation_targets = training_participation_targets_for_week(participation_targets, selected_week) if selected_week.present?
    participation_dashboard_counts = training_participation_dashboard_counts(
      month_name: selected_month,
      fcoc_name: selected_fcoc,
      records: training_records,
      targets: participation_targets,
      week_number: selected_week
    )
    population_rows = nil
    target_map_rows = nil
    record_rows = nil

    @training_participation_status = selected_status
    @training_participation_title = training_participation_status_label(selected_status)
    @training_participation_caption = training_participation_status_caption(selected_status)
    @training_participation_rows = if selected_status == "unique" || selected_status == "mapped"
      farmer_training_participation_rows_from_sql(
        "unique",
        month_name: selected_month,
        fcoc_name: selected_fcoc
      )
    elsif %w[no_activity no_training_mapping no_training training_mapped_no_entry no_entry red total_red pending].include?(selected_status)
      farmer_training_participation_rows_from_sql(
        selected_status,
        month_name: selected_month,
        fcoc_name: selected_fcoc
      )
    elsif selected_status == "yellow" || selected_status == "only_1_training" || selected_status == "1_training"
      farmer_training_participation_rows_from_sql(
        "yellow",
        month_name: selected_month,
        fcoc_name: selected_fcoc,
        week_number: selected_week
      )
    elsif selected_status == "green" || selected_status == "1_plus_trainings" || selected_status == "more_than_1"
      farmer_training_participation_rows_from_sql(
        "green",
        month_name: selected_month,
        fcoc_name: selected_fcoc,
        week_number: selected_week
      )
    elsif selected_status == "training_unique"
      record_rows = training_participation_farmer_rows_from_records(training_records)
    elsif selected_status == "completed_map"
      target_map_rows = training_participation_target_map_rows(participation_targets, month_name: selected_month)
      target_map_rows.select { |row| row[:completed_activity_count].to_i.positive? }
    elsif selected_status == "pending_achievement"
      target_map_rows = training_participation_target_map_rows(participation_targets, month_name: selected_month)
      target_map_rows.select { |row| row[:completed_activity_count].to_i < row[:assigned_activity_count].to_i }
    elsif selected_status == "total"
      target_map_rows = training_participation_target_map_rows(participation_targets, month_name: selected_month)
      target_map_rows
    else
      record_rows = training_participation_farmer_rows_from_records(training_records)
      record_rows.select { |row| row[:status] == selected_status }
    end
    mapped_sql_count, mapped_sql_popups = farmer_training_mapped_farmer_count_and_popups(
      month_name: selected_month,
      fcoc_name: selected_fcoc
    )
    no_training_sql_count, no_training_sql_popups = farmer_training_no_training_count_and_popups(
      month_name: selected_month,
      fcoc_name: selected_fcoc
    )
    yellow_sql_count, yellow_sql_popups = farmer_training_yellow_farmer_count_and_popups(
      month_name: selected_month,
      fcoc_name: selected_fcoc
    )
    green_sql_count, green_sql_popups = farmer_training_green_farmer_count_and_popups(
      month_name: selected_month,
      fcoc_name: selected_fcoc
    )

    @training_participation_totals = participation_dashboard_counts.slice(:green, :yellow, :red, :pending, :total)
    @training_selected_week = selected_week
    @training_unique_farmer_count = mapped_sql_count
    @training_mapped_farmer_count = mapped_sql_count
    @training_mapped_farmer_popups = mapped_sql_popups
    @training_no_training_popups = no_training_sql_popups
    @training_yellow_farmer_popups = yellow_sql_popups
    @training_green_farmer_popups = green_sql_popups
    @training_total_training_farmer_count = participation_dashboard_counts[:target_map_total].to_i
    @training_completed_target_map_count = participation_dashboard_counts[:completed_target_map_total].to_i
    @training_participation_totals[:unique] = mapped_sql_count
    @training_participation_totals[:red] = no_training_sql_count
    @training_participation_totals[:pending] = no_training_sql_count
    @training_participation_totals[:yellow] = yellow_sql_count
    @training_participation_totals[:green] = green_sql_count
    @training_participation_totals[:total] = @training_total_training_farmer_count
    @training_participation_totals[:completed_map] = @training_completed_target_map_count
    @training_selected_month = selected_month
    @training_selected_sub_activity = selected_sub_activity
    @training_selected_fcoc = selected_fcoc
    @training_selected_method = selected_training_method
    enrich_training_participation_list_rows!(@training_participation_rows, training_records, participation_targets)
    @training_participation_search = params[:search].to_s.strip
    if @mapped_farmer_details
      columns = @mapped_farmer_details.columns | %w[training_register_urls training_photo_urls]
      details = @mapped_farmer_details.to_a.each_with_index.map do |detail, index|
        row = @training_participation_rows[index]
        detail.merge("cluster_incharge" => row[:cluster_incharge],
          "training_register_urls" => Array(row[:training_register_urls]).join(", "),
          "training_photo_urls" => Array(row[:training_photo_urls]).join(", "))
      end
      if @training_participation_search.present?
        matching = details.each_index.select { |index| training_participation_search_match?(details[index].values) }
        details = matching.map { |index| details[index] }
        @training_participation_rows = matching.map { |index| @training_participation_rows[index] }
      end
      @mapped_farmer_details = ActiveRecord::Result.new(columns, details.map { |detail| columns.map { |column| detail[column] } })
    elsif @training_participation_search.present?
      @training_participation_rows = @training_participation_rows.select { |row| training_participation_search_match?(row.values) }
    end
    @training_participation_total_count = @training_participation_rows.size
    @training_participation_page = [params[:page].to_i, 1].max
    per_page_value = params[:per_page].present? ? params[:per_page].to_i : 20
    @training_participation_per_page = [[per_page_value, 20].max, 500].min
    @training_participation_total_pages = [(@training_participation_total_count.to_f / @training_participation_per_page).ceil, 1].max
    @training_participation_page = @training_participation_total_pages if @training_participation_page > @training_participation_total_pages
    @training_participation_page_rows = @training_participation_rows.slice((@training_participation_page - 1) * @training_participation_per_page, @training_participation_per_page) || []

    if @mapped_farmer_details
      # Paginate the rendered rows so the browser does not build all 9k+ <tr> at once
      # (that froze the page). Counts and exports still use the full result below.
      @training_participation_total_count = @mapped_farmer_details.rows.size
      @training_participation_total_pages = [(@training_participation_total_count.to_f / @training_participation_per_page).ceil, 1].max
      @training_participation_page = [[@training_participation_page, @training_participation_total_pages].min, 1].max
    end
    if @mapped_farmer_details && request.format.csv?
      send_data(CSV.generate { |csv| csv << @mapped_farmer_details.columns; @mapped_farmer_details.rows.each { |row| csv << row } },
        filename: "#{@training_participation_status}-farmers.csv", type: "text/csv")
      return
    end
    if @mapped_farmer_details && request.format.xlsx?
      send_xlsx(headers: @mapped_farmer_details.columns, rows: @mapped_farmer_details.rows,
        filename: "#{@training_participation_status}-farmers-#{selected_month.presence || 'all-months'}.xlsx", sheet_name: "Farmer Details")
      return
    end

    # HTML only: render just the current page's rows so the DOM stays small (no freeze).
    if @mapped_farmer_details
      page_rows = @mapped_farmer_details.rows.slice((@training_participation_page - 1) * @training_participation_per_page, @training_participation_per_page) || []
      @mapped_farmer_details = ActiveRecord::Result.new(@mapped_farmer_details.columns, page_rows)
    end

    respond_to do |format|
      format.html
      format.csv do
        send_data(
          training_participation_rows_csv(@training_participation_rows),
          filename: "farmer-training-#{selected_status}-#{Time.current.strftime("%Y%m%d%H%M")}.csv",
          type: "text/csv"
        )
      end
      format.xlsx do
        send_xlsx(
          headers: training_participation_export_headers,
          rows: training_participation_export_rows(@training_participation_rows),
          filename: "farmer-training-#{selected_status}-#{Time.current.strftime("%Y%m%d%H%M")}.xlsx",
          sheet_name: "Training Participation"
        )
      end
      format.zip do
        send_data(
          training_participation_attachments_zip(@training_participation_rows),
          filename: "farmer-training-attachments-#{selected_status}-#{Time.current.strftime("%Y%m%d%H%M")}.zip",
          type: "application/zip"
        )
      end
    end
  end

  private

  def dashboard_filter_sub_activity_options(targets)
    month = params.key?(:month) ? dashboard_filter_param(:month) : nil
    fcoc = dashboard_filter_param(:fcoc, :fco)
    fco_values = training_fcoc_filter_values(fcoc) if fcoc.present?
    ics = dashboard_filter_param(:ics, :ics_name)
    cluster = dashboard_filter_param(:cluster_incharge)
    vrp_id = dashboard_filter_param(:vrp_id)
    post = dashboard_filter_param(:post)
    Array(targets).select do |target|
      (month.blank? || normalize_dashboard_text(target.month_name) == normalize_dashboard_text(month)) &&
        (fco_values.blank? || (training_fcoc_filter_values(target.fco_name, target.fco_id, target.vrp&.fcoc) & fco_values).any?) &&
        (ics.blank? || (target.ics_name.presence || target.ics_id).to_s == ics) &&
        (cluster.blank? || cluster_label_matches?(cluster, target.vrp&.cluster_incharge)) &&
        (vrp_id.blank? || target.vrp_id.to_s == vrp_id) &&
        (post.blank? || target.vrp&.role.to_s == post)
    end.map(&:activity_name).uniq.compact_blank.sort
  end

  # Main Major Work Indicator - Other. The box and its list both read the saved
  # Other Target entries: target and achievement are summed from those entries,
  # and the hover popup breaks them down per FCO. Only this panel uses them.

  def dashboard_other_activity_totals(_targets = nil)
    rows = dashboard_other_target_entry_rows
    target = rows.sum { |row| row["target"].to_f }
    achievement = rows.sum { |row| row["achievement"].to_f }
    activities = rows.filter_map { |row| row["main_activity"].presence }.uniq
    by_fco = {}
    row_fco_names = {}
    rows.each do |row|
      key = dashboard_bare_fco_name(row["fco_name"])
      row_fco_names[key] ||= row["fco_name"].to_s.sub(/\Afco\s*-?\s*c?\s*/i, "").strip
      totals = by_fco[key] ||= [0.0, 0.0]
      totals[0] += row["target"].to_f
      totals[1] += row["achievement"].to_f
    end

    # The breakdown always lists every project FCO, including ones with nothing
    # recorded yet. Grouping only what exists made "All FCO" show a single FCO,
    # which reads as a filter bug rather than as missing data. Any FCO that does
    # have rows is added too, so the box total always has a popup line behind it
    # -- an office with entries but no farmers loaded yet would otherwise be
    # counted in the total and missing from the breakdown.
    selected_fco = dashboard_filter_param(:fcoc, :fco)
    listed_fcos =
      if selected_fco.present?
        [selected_fco.to_s.sub(/\Afco\s*-?\s*c?\s*/i, "").strip]
      else
        known = dashboard_fco_names
        extra = row_fco_names.reject { |key, _| known.any? { |name| dashboard_bare_fco_name(name) == key } }
        (known + extra.values.compact_blank).uniq
      end

    {
      main_major_work_indicator: activities.size,
      mapped_farmer: dashboard_amount_text(target),
      achievement_farmer: dashboard_amount_text(achievement),
      pending_farmer: dashboard_amount_text([target - achievement, 0].max),
      achieved: target.positive? ? (achievement * 100.0 / target).round(2) : 0,
      main_major_work_indicator_popups: listed_fcos.map do |name|
        fco_target, fco_achievement = by_fco.fetch(dashboard_bare_fco_name(name), [0.0, 0.0])
        "#{name} = #{dashboard_amount_text(fco_achievement)}/#{dashboard_amount_text(fco_target)}"
      end
    }
  end

  # "FCO-C Sausar" and "Sausar" are the same office; compare on the bare name.

  def dashboard_bare_fco_name(value)
    normalize_dashboard_text(value.to_s.sub(/\Afco\s*-?\s*c?\s*/i, ""))
  end

  # Whole numbers stay whole; only genuine fractions keep decimals.

  def dashboard_amount_text(value)
    value.to_f == value.to_f.round ? value.to_f.round : value.to_f.round(2)
  end

  # Saved Other Target entries for the selected month and FCO. Used only by the
  # "Main Major Work Indicator - Other" box; the mobile other_activities list
  # still uses dashboard_other_activity_rows.

  def dashboard_cards
    vrps = dashboard_vrps
    active_vrps = vrps.select do |vrp|
      is_act = vrp.respond_to?(:is_active) ? (vrp.is_active == true || vrp.is_active == 1) : true
      is_del = vrp.respond_to?(:is_deleted) ? (vrp.is_deleted == true || vrp.is_deleted == 1) : false
      is_act && !is_del
    end
    approved_vrps = dashboard_approved_vrps(active_vrps).size
    pending_approvals = dashboard_pending_approval_vrps(active_vrps).size

    bill_records = dashboard_billing_records
    # Move the Jeevika Jankar Billing counts with the dashboard month filter:
    # when a month is chosen, only that month's bills are counted (bill_month).
    selected_bill_month = @dashboard_month_filter_value.presence
    selected_bill_month = nil if selected_bill_month.to_s.casecmp("all").zero?
    if selected_bill_month.present?
      bill_records = bill_records.select do |r|
        normalize_dashboard_text(r.data["bill_month"].presence || r.data["select_bill_month"]) ==
          normalize_dashboard_text(selected_bill_month)
      end
    end
    bill_month_filter = { bill_month: selected_bill_month }.compact
    approved_bills = bill_records.count { |r| dashboard_bill_approved?(r) }
    pending_bills = bill_records.count { |r| dashboard_bill_pending?(r) }
    billing_items = [
      { title: "Approved", value: approved_bills, path: module_path("jeevika-jankar-bill-list", { bill_status: "final-approved", record_state: "Active" }.merge(bill_month_filter)) },
      { title: "Pending", value: pending_bills, path: module_path("jeevika-jankar-bill-list", { bill_status: "pending", record_state: "Active" }.merge(bill_month_filter)) }
    ]

    cards = [
      dashboard_group_card("Jeevika Jankar Registration", [
        { title: "Total Registered", value: active_vrps.size, path: vrps_path(active_status: "active") },
        { title: "Final Approved", value: approved_vrps, path: vrps_path(approval_status: "final-approved", active_status: "active") },
        { title: "Pending Approval", value: pending_approvals, path: approvals_vrps_path }
      ], style: "registration"),
      dashboard_group_card("Jeevika Jankar Billing", billing_items, style: "billing")
    ]
    fco_names = dashboard_fco_names
    gender_month = (params.key?(:month) ? dashboard_filter_param(:month) : dashboard_filter_param(:training_month).presence || DashboardDefaults.month)
    gender_items = fco_names.flat_map do |fco_name|
      # Same JJ set as the FCO-wise JJ Requirement "Active" box, split by gender.
      fco_vrps = dashboard_fco_active_vrp_records(fco_name, gender_month, vrps)
      [
        { title: "#{fco_name} Male", value: fco_vrps.count { |vrp| normalize_dashboard_text(vrp.gender) == "male" }, path: vrps_path(gender: "male", fcoc: fco_name, active_status: "active") },
        { title: "#{fco_name} Female", value: fco_vrps.count { |vrp| normalize_dashboard_text(vrp.gender) == "female" }, path: vrps_path(gender: "female", fcoc: fco_name, active_status: "active") }
      ]
    end
    cards << dashboard_group_card("Gender Count", gender_items, style: "registration")
    cards << dashboard_group_card("FCO-wise JJ Requirement", fco_names.flat_map { |fco_name| dashboard_jj_requirement_items(fco_name, vrps, defined?(@filtered_targets) ? @filtered_targets : nil) }, style: "fco")

    cards
  end

  def dashboard_summary_query_counts
    return nil unless model_ready?(:TargetMapping)

    target_conditions, binds = dashboard_summary_target_sql_filters
    target_where = target_conditions.join(" AND ")
    sql = <<~SQL.squish
      WITH mapped_rows AS (
        SELECT
          j.value AS afl_id
        FROM target_mappings t
        LEFT JOIN vrps v ON v.id = t.vrp_id
        CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
            ELSE jsonb_build_array(t.afl_ids::jsonb)
          END
        ) AS j(value)
        WHERE #{target_where}
      )
      SELECT
        COUNT(DISTINCT mapped_rows.afl_id) AS mapped_farmer_count
      FROM mapped_rows
    SQL

    row = dashboard_sql_cache.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, binds])
    ).first || {}

    activity_counts = dashboard_summary_activity_counts_direct

    {
      ics_count: dashboard_total_afl_ics_count,
      village_count: dashboard_total_afl_village_count,
      farmer_count: dashboard_total_afl_farmer_count,
      mapped_farmer_count: row["mapped_farmer_count"].to_i,
      main_activity_count: activity_counts[:main_activity_count],
      sub_activity_count: activity_counts[:sub_activity_count]
    }
  rescue StandardError => e
    Rails.logger.warn("Dashboard summary query counts failed: #{e.class} - #{e.message}")
    nil
  end

  def dashboard_summary_activity_counts_direct
    return { main_activity_count: 0, sub_activity_count: 0 } unless model_ready?(:TargetMapping)

    target_conditions, binds = dashboard_summary_target_sql_filters_base(include_activity_filters: false)
    target_where = target_conditions.join(" AND ")
    sql = <<~SQL.squish
      SELECT
        COUNT(DISTINCT NULLIF(LOWER(BTRIM(t.main_activity_name)), '')) AS main_activity_count,
        COUNT(DISTINCT NULLIF(LOWER(BTRIM(t.activity_name)), '')) AS sub_activity_count
      FROM target_mappings t
      LEFT JOIN vrps v ON v.id = t.vrp_id
      WHERE #{target_where}
    SQL

    row = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, binds])
    ).first || {}

    {
      main_activity_count: row["main_activity_count"].to_i,
      sub_activity_count: row["sub_activity_count"].to_i
    }
  rescue StandardError => e
    { main_activity_count: 0, sub_activity_count: 0 }
  end

  # Builds the WHERE clause behind every dashboard summary card. The table
  # aliases are configurable so the same predicate can be reused by the
  # "View List" pages, which join through ActiveRecord's real table names.

  def dashboard_summary_target_sql_filters_base(include_activity_filters: true, target_alias: "t", vrp_alias: "v")
    conditions = ["1=1"]
    binds = {}
    unless dashboard_global_view_user?
      conditions << "#{target_alias}.vrp_id IN (:authorized_vrp_ids)"
      binds[:authorized_vrp_ids] = dashboard_visible_vrp_ids
    end

    month_value = @dashboard_month_filter_value.presence || dashboard_filter_param(:month, :training_month)
    if month_value.present?
      conditions << "LOWER(BTRIM(#{target_alias}.month_name)) = :summary_month"
      binds[:summary_month] = normalize_dashboard_text(month_value)
    end

    if include_activity_filters
      main_activity_value = @dashboard_main_activity_filter_value.presence || dashboard_filter_param(:main_activity)
      if main_activity_value.present?
        conditions << "LOWER(BTRIM(#{target_alias}.main_activity_name)) = :summary_main_activity"
        binds[:summary_main_activity] = normalize_dashboard_text(main_activity_value)
      end

      sub_activity_value = dashboard_filter_param(:sub_activity)
      if sub_activity_value.present?
        conditions << "LOWER(BTRIM(#{target_alias}.activity_name)) = :summary_sub_activity"
        binds[:summary_sub_activity] = normalize_dashboard_text(sub_activity_value)
      end
    end

    fcoc_value = @dashboard_fcoc_filter_value.presence || dashboard_filter_param(:fcoc, :fco)
    fco_values = dashboard_summary_fco_filter_values(fcoc_value)
    if fco_values.any?
      conditions << "(LOWER(BTRIM(#{target_alias}.fco_name)) IN (:summary_fco_values) OR LOWER(BTRIM(#{target_alias}.fco_id)) IN (:summary_fco_values) OR LOWER(BTRIM(#{vrp_alias}.fcoc)) IN (:summary_fco_values))"
      binds[:summary_fco_values] = fco_values
    end

    ics_value = dashboard_filter_param(:ics, :ics_name)
    if ics_value.present?
      conditions << "(LOWER(BTRIM(#{target_alias}.ics_name)) = :summary_ics OR LOWER(BTRIM(#{target_alias}.ics_id)) = :summary_ics)"
      binds[:summary_ics] = normalize_dashboard_text(ics_value)
    end

    selected_vrp_id = dashboard_filter_param(:vrp_id)
    if selected_vrp_id.present?
      conditions << "#{target_alias}.vrp_id = :summary_vrp_id"
      binds[:summary_vrp_id] = selected_vrp_id.to_i
    elsif vrp_login_user? && current_vrp_record.present?
      conditions << "#{target_alias}.vrp_id = :summary_vrp_id"
      binds[:summary_vrp_id] = current_vrp_record.id
    elsif dashboard_agronomics_login? && !dashboard_agronomist_all_months?
      conditions << "#{target_alias}.vrp_id IN (:summary_registered_vrp_ids)"
      binds[:summary_registered_vrp_ids] = dashboard_registered_vrp_ids_for_current_user
    elsif dashboard_cc_vrp_scope_active?
      conditions << "#{target_alias}.vrp_id IN (:summary_visible_vrp_ids)"
      binds[:summary_visible_vrp_ids] = module_cluster_visible_vrp_ids
    end

    [conditions, binds]
  end

  # The "View List" behind the Total Mapped Main/Sub Work Indicator cards has to
  # count exactly what the card counted, so it reuses the card's own predicate
  # instead of re-deriving the filters from the query string.

  def dashboard_summary_target_scope(include_activity_filters: false)
    conditions, binds = dashboard_summary_target_sql_filters_base(
      include_activity_filters: include_activity_filters,
      target_alias: "target_mappings",
      vrp_alias: "vrps"
    )
    TargetMapping.left_joins(:vrp).where(conditions.join(" AND "), binds)
  end

  def dashboard_summary_direct_afl_total?
    !vrp_login_user? && !dashboard_agronomics_login? && !dashboard_cc_vrp_scope_active?
  end

  def demonstration_method_cards
    report = @demonstration_method_report || DashboardDemonstrationMethodReport.new(
      targets: @filtered_targets || dashboard_target_mappings,
      month: params.key?(:month) ? dashboard_filter_param(:month) : DashboardDefaults.month, cache: dashboard_sql_cache)

    summary_rows = report.summary

    gen_target = summary_rows.sum { |r| r["General Training/Meeting Target"].to_f }.to_i
    gen_done   = summary_rows.sum { |r| r["General Training/Meeting Done"].to_f }.to_i
    gen_val    = "#{gen_target} / #{gen_done}"

    inm_target = summary_rows.sum { |r| r["Input Demo INM Target"].to_f }.to_i
    inm_done   = summary_rows.sum { |r| r["Input Demo INM Done"].to_f }.to_i
    inm_val    = "#{inm_target} / #{inm_done}"

    pm_target  = summary_rows.sum { |r| r["Input Demo PM Target"].to_f }.to_i
    pm_done    = summary_rows.sum { |r| r["Input Demo PM Done"].to_f }.to_i
    pm_val     = "#{pm_target} / #{pm_done}"

    ffs_target = summary_rows.sum { |r| r["FFS Target"].to_f }.to_i
    ffs_done   = summary_rows.sum { |r| r["FFS Done"].to_f }.to_i
    ffs_val    = "#{ffs_target} / #{ffs_done}"

    # OPG Training Target's own count stays the Target half; its Achievement
    # half is the sum of what the other four Demonstration Method boxes have
    # already achieved, not a separately tracked OPG achievement figure.
    opg_target = dashboard_quantity(summary_rows.sum { |r| r["OPG Target"].to_f })
    opg_achievement = gen_done + inm_done + pm_done + ffs_done
    opg_val = "#{opg_target} / #{opg_achievement}"

    # Use exactly the same JJ-level CC calculation as the Demonstration Method
    # View List, then aggregate it for the active FCO/month dashboard filters.
    cc_metrics = report.rows.map { |row| row["CC TARGET STATUS"].to_s.split("/").map(&:to_i) }
    cc_target = cc_metrics.sum { |target, _achievement| target }
    cc_done = cc_metrics.sum { |_target, achievement| achievement }
    cc_val = "#{cc_target} / #{cc_done}"

    card_list_path = demonstration_method_list_path(request.query_parameters)
    card_xlsx_path = demonstration_method_list_path(request.query_parameters.merge(format: :xlsx))

    [
      dashboard_summary_card("OPG Training Target", opg_val, "Training method entries", card_list_path, card_xlsx_path),
      dashboard_summary_card("General Training/Meeting", gen_val, "Training method entries", card_list_path, card_xlsx_path),
      dashboard_summary_card("Input Demo INM", inm_val, "Training method entries", card_list_path, card_xlsx_path),
      dashboard_summary_card("Input Demo PM", pm_val, "Training method entries", card_list_path, card_xlsx_path),
      dashboard_summary_card("FFS Exposure", ffs_val, "Training method entries", card_list_path, card_xlsx_path),
      dashboard_summary_card("CC TARGET STATUS", cc_val, "Demonstration Method target / achievement", card_list_path, card_xlsx_path)
    ]
  end

  def dashboard_opg_achievement_count
    return 0 unless model_ready?(:ModuleRecord)

    month_value = @participation_selected_month.presence || @dashboard_month_filter_value.presence
    fcoc_value = @participation_fcoc_filter_value.presence || @dashboard_fcoc_filter_value.presence || dashboard_filter_param(:fcoc, :fco)
    selected_vrp_id = dashboard_filter_param(:vrp_id)

    training_conditions = ["mr.module_slug = 'training-form'", "sf.farmer_id <> ''"]
    if !dashboard_global_view_user? || dashboard_filter_param(:ics, :ics_name).present?
      training_conditions << "sf.farmer_id IN (#{dashboard_visible_farmer_scope.select('afls.id::text').to_sql})"
    end
    training_binds = {}

    if month_value.present?
      training_conditions << "LOWER(COALESCE(mr.data::jsonb ->> 'month', '')) = :training_month"
      training_binds[:training_month] = normalize_dashboard_text(month_value)
    end

    if selected_vrp_id.present?
      training_conditions << "mr.data::jsonb ->> 'created_by_id' = :created_by_id"
      training_binds[:created_by_id] = selected_vrp_id.to_s
    elsif vrp_login_user? && current_vrp_record.present?
      training_conditions << "mr.data::jsonb ->> 'created_by_id' = :created_by_id"
      training_binds[:created_by_id] = current_vrp_record.id.to_s
    elsif dashboard_agronomics_login? && !dashboard_agronomist_all_months?
      training_conditions << "COALESCE(mr.data::jsonb ->> 'created_by_id', '') IN (:created_by_ids)"
      training_binds[:created_by_ids] = dashboard_registered_vrp_ids_for_current_user.map(&:to_s)
    elsif dashboard_cc_vrp_scope_active?
      training_conditions << "COALESCE(mr.data::jsonb ->> 'created_by_id', '') IN (:created_by_ids)"
      training_binds[:created_by_ids] = module_cluster_visible_vrp_ids.map(&:to_s)
    end

    fco_values = dashboard_summary_fco_filter_values(fcoc_value)
    if fco_values.present?
      training_conditions << "LOWER(COALESCE(mr.data::jsonb ->> 'trainee_department', '')) IN (:fco_values)"
      training_binds[:fco_values] = fco_values
    end

    sql = <<~SQL.squish
      SELECT COUNT(DISTINCT sf.farmer_id)
      FROM module_records mr
      CROSS JOIN LATERAL jsonb_array_elements_text(
        COALESCE(mr.data::jsonb -> 'selected_farmer_ids', '[]'::jsonb)
      ) AS sf(farmer_id)
      WHERE #{training_conditions.join(' AND ')}
    SQL

    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, training_binds])
    ).to_i
  rescue StandardError => e
    Rails.logger.warn("OPG achievement count failed: #{e.class} - #{e.message}")
    0
  end

  def dashboard_training_method_counts
    return training_method_count_defaults unless model_ready?(:TargetMapping) && model_ready?(:ModuleRecord)

    month_value = @participation_selected_month.presence || @dashboard_month_filter_value.presence
    fcoc_value = @participation_fcoc_filter_value.presence || @dashboard_fcoc_filter_value.presence || dashboard_filter_param(:fcoc, :fco)
    selected_vrp_id = dashboard_filter_param(:vrp_id)
    target_conditions = ["j.value <> ''"]
    unless dashboard_global_view_user?
      target_conditions << "t.vrp_id IN (#{Vrp.where(id: dashboard_visible_vrp_ids).select(:id).to_sql})"
    end
    target_binds = {}
    if month_value.present?
      target_conditions << "LOWER(BTRIM(t.month_name)) = :target_month"
      target_binds[:target_month] = normalize_dashboard_text(month_value)
    end
    target_conditions << "LOWER(BTRIM(t.main_activity_name)) = :target_main_activity"
    target_binds[:target_main_activity] = normalize_dashboard_text("Farmers' Training")
    if dashboard_filter_param(:sub_activity).present?
      target_conditions << "LOWER(BTRIM(t.activity_name)) = :target_sub_activity"
      target_binds[:target_sub_activity] = normalize_dashboard_text(dashboard_filter_param(:sub_activity))
    end
    fco_values = dashboard_summary_fco_filter_values(fcoc_value)
    target_conditions << "(LOWER(BTRIM(t.fco_name)) IN (:fco_values) OR LOWER(BTRIM(t.fco_id)) IN (:fco_values) OR LOWER(BTRIM(v.fcoc)) IN (:fco_values))"
    target_binds[:fco_values] = fco_values
    if selected_vrp_id.present?
      target_conditions << "t.vrp_id = :target_vrp_id"
      target_binds[:target_vrp_id] = selected_vrp_id.to_i
    elsif vrp_login_user? && current_vrp_record.present?
      target_conditions << "t.vrp_id = :target_vrp_id"
      target_binds[:target_vrp_id] = current_vrp_record.id
    elsif dashboard_agronomics_login? && !dashboard_agronomist_all_months?
      target_conditions << "t.vrp_id IN (:target_registered_vrp_ids)"
      target_binds[:target_registered_vrp_ids] = dashboard_registered_vrp_ids_for_current_user
    elsif dashboard_cc_vrp_scope_active?
      target_conditions << "t.vrp_id IN (:target_visible_vrp_ids)"
      target_binds[:target_visible_vrp_ids] = module_cluster_visible_vrp_ids
    end
    if dashboard_filter_param(:ics, :ics_name).present?
      target_conditions << "(LOWER(BTRIM(t.ics_name)) = :target_ics OR LOWER(BTRIM(t.ics_id)) = :target_ics)"
      target_binds[:target_ics] = normalize_dashboard_text(dashboard_filter_param(:ics, :ics_name))
    end

    training_conditions = ["mr.module_slug = 'training-form'", "sf.farmer_id <> ''"]
    if !dashboard_global_view_user? || dashboard_filter_param(:ics, :ics_name).present?
      training_conditions << "sf.farmer_id IN (#{dashboard_visible_farmer_scope.select('afls.id::text').to_sql})"
    end
    training_binds = {}
    if month_value.present?
      training_conditions << "LOWER(COALESCE(mr.data::jsonb ->> 'month', '')) = :training_month"
      training_binds[:training_month] = normalize_dashboard_text(month_value)
    end
    if selected_vrp_id.present?
      training_conditions << "mr.data::jsonb ->> 'created_by_id' = :created_by_id"
      training_binds[:created_by_id] = selected_vrp_id.to_s
    elsif vrp_login_user? && current_vrp_record.present?
      training_conditions << "mr.data::jsonb ->> 'created_by_id' = :created_by_id"
      training_binds[:created_by_id] = current_vrp_record.id.to_s
    elsif dashboard_agronomics_login? && !dashboard_agronomist_all_months?
      training_conditions << "COALESCE(mr.data::jsonb ->> 'created_by_id', '') IN (:created_by_ids)"
      training_binds[:created_by_ids] = dashboard_registered_vrp_ids_for_current_user.map(&:to_s)
    end

    sql = <<~SQL.squish
      WITH mapped_farmers AS MATERIALIZED (
        SELECT DISTINCT j.value AS afl_id
        FROM target_mappings t
        LEFT JOIN vrps v ON v.id = t.vrp_id
        CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
            ELSE jsonb_build_array(t.afl_ids::jsonb)
          END
        ) AS j(value)
        WHERE #{target_conditions.join(' AND ')}
      ),
      training_entries AS MATERIALIZED (
        SELECT DISTINCT
          sf.farmer_id,
          BTRIM(mr.data::jsonb ->> 'training_method') AS training_method
        FROM module_records mr
        CROSS JOIN LATERAL jsonb_array_elements_text(
          COALESCE(mr.data::jsonb -> 'selected_farmer_ids', '[]'::jsonb)
        ) AS sf(farmer_id)
        WHERE #{training_conditions.join(' AND ')}
      )
      SELECT
        COUNT(DISTINCT mf.afl_id) FILTER (WHERE te.training_method = 'General Training/Meeting') AS general_training_meeting,
        COUNT(DISTINCT mf.afl_id) FILTER (WHERE te.training_method = 'Input Demo INM') AS input_demo_inm,
        COUNT(DISTINCT mf.afl_id) FILTER (WHERE te.training_method = 'FFS') AS ffs,
        COUNT(DISTINCT mf.afl_id) FILTER (WHERE UPPER(te.training_method) = 'INPUT DEMO PM') AS input_demo_pm,
        COUNT(DISTINCT mf.afl_id) FILTER (WHERE UPPER(te.training_method) = 'OPG') AS opg
      FROM mapped_farmers mf
      LEFT JOIN training_entries te ON te.farmer_id = mf.afl_id
    SQL

    row = dashboard_sql_cache.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, target_binds.merge(training_binds)])
    ).first || {}
    {
      "General Training/Meeting" => row["general_training_meeting"].to_i,
      "Input Demo INM" => row["input_demo_inm"].to_i,
      "FFS" => row["ffs"].to_i,
      "Input Demo PM" => row["input_demo_pm"].to_i,
      "OPG" => row["opg"].to_i
    }
  rescue StandardError => e
    Rails.logger.warn("Dashboard training method counts failed: #{e.class} - #{e.message}")
    training_method_count_defaults
  end

  def dashboard_jj_requirement_items(fco_name, vrps, targets = nil)
    normalized_fco = normalize_dashboard_text(fco_name)
    fco_id = DashboardFcoDirectory.office_for(fco_name)&.dig(:id).presence || DashboardFcoDirectory.id_for(fco_name).presence || if normalized_fco.include?("1004") || normalized_fco.include?("sausar")
               "1004"
             elsif normalized_fco.include?("1006") || normalized_fco.include?("turekela")
               "1006"
             elsif normalized_fco.include?("1095") || normalized_fco.include?("pavijetpur")
               "1095"
             else
               nil
             end

    selected_month = (params.key?(:month) ? dashboard_filter_param(:month) : dashboard_filter_param(:training_month).presence || DashboardDefaults.month)
    active_count   = dashboard_fco_active_vrp_count(fco_name, selected_month, vrps)

    if normalized_fco.include?("sausar") || fco_id == "1004"
      required_count = [34, active_count].max
    elsif normalized_fco.include?("turekela") || fco_id == "1006"
      required_count = [24, active_count].max
    else
      fco_aliases = DashboardFcoDirectory.aliases_for(fco_name).map { |value| normalize_dashboard_text(value) }
      fco_aliases << normalized_fco
      fco_targets = Array(targets).select do |target|
        target_values = [target.fco_name, target.fco_id, target.vrp&.fcoc].compact.map { |value| normalize_dashboard_text(value) }
        target_values.any? { |value| fco_aliases.include?(value) }
      end
      req            = fco_targets.map { |t| normalize_dashboard_text(t.village_name) }.reject(&:blank?).uniq.size
      required_count = [req, active_count].max
    end

    vacant_count = [required_count - active_count, 0].max

    [
      { title: "#{fco_name} Required", value: required_count, path: target_mappings_path(fcoc: fco_name) },
      { title: "#{fco_name} Active", value: active_count, path: vrps_path(fcoc: fco_name, active_status: "active", approval_status: "final-approved") },
      { title: "#{fco_name} Vacant", value: vacant_count, path: vrps_path(fcoc: fco_name, active_status: "vacant") }
    ]
  end

  def dashboard_summary_activity_target_params
    dashboard_summary_target_params.except("main_activity", "sub_activity")
  end

  def dashboard_weekly_report_filter_params
    params_hash = {
      training_month: params[:month].presence || params[:training_month].presence,
      main_activity: params[:main_activity].presence || @dashboard_main_activity_filter_value.presence,
      activity: params[:activity].presence || params[:main_activity].presence || @dashboard_main_activity_filter_value.presence,
      training_sub_activity: params[:training_sub_activity].presence || params[:sub_activity].presence,
      training_fcoc: params[:weekly_target_fcoc].presence || params[:fcoc].presence,
      week: params[:weekly_target_week].presence,
      cluster_incharge: params[:cluster_incharge].presence,
      post: params[:post].presence,
      vrp_id: params[:vrp_id].presence
    }.compact_blank
    params_hash[:fco_id] = DashboardFcoDirectory.ids if params_hash[:training_fcoc].blank?
    params_hash
  end

  def training_participation_targets_for_dashboard(month_name: nil, fcoc_name: nil, main_activity_name: nil, sub_activity_name: nil)
    @training_participation_targets_cache ||= {}
    cache_key = [normalize_dashboard_text(month_name), normalize_dashboard_text(fcoc_name), normalize_dashboard_text(main_activity_name), normalize_dashboard_text(sub_activity_name)]
    return @training_participation_targets_cache[cache_key] if @training_participation_targets_cache.key?(cache_key)

    targets = dashboard_participation_targets
    targets = training_participation_active_vrp_targets(targets)
    if dashboard_filter_param(:ics, :ics_name).present?
      selected_ics = normalize_dashboard_text(dashboard_filter_param(:ics, :ics_name))
      targets = targets.select { |target| [target.ics_id, target.ics_name].any? { |value| normalize_dashboard_text(value) == selected_ics } }
    end

    targets = dashboard_targets_for_month(targets, month_name) if month_name.present?
    if fcoc_name.present?
      targets = Array(targets).select { |target| training_target_matches_fcoc?(target, fcoc_name) }
    end
    if main_activity_name.present?
      normalized_main_activity = normalize_dashboard_text(main_activity_name)
      targets = Array(targets).select { |target| normalize_dashboard_text(target.main_activity_name) == normalized_main_activity }
    end
    if sub_activity_name.present?
      normalized_sub_activity = normalize_dashboard_text(sub_activity_name)
      targets = Array(targets).select { |target| normalize_dashboard_text(target.activity_name) == normalized_sub_activity }
    end
    @training_participation_targets_cache[cache_key] = targets
  end

  def dashboard_training_participation_records(month_name: nil, main_activity_name: nil, sub_activity_name: nil, fcoc_name: nil)
    return [] unless model_ready?(:ModuleRecord)

    @dashboard_training_participation_records_cache ||= {}
    cache_key = [normalize_dashboard_text(month_name), normalize_dashboard_text(main_activity_name), normalize_dashboard_text(sub_activity_name), normalize_dashboard_text(fcoc_name)]
    return @dashboard_training_participation_records_cache[cache_key] if @dashboard_training_participation_records_cache.key?(cache_key)

    targets = training_participation_targets_for_dashboard(month_name: month_name, fcoc_name: fcoc_name, main_activity_name: main_activity_name, sub_activity_name: sub_activity_name)
    farmer_ids = training_participation_valid_farmer_ids_for_targets(targets)
    records = active_module_records_scope("training-form")
      # training_record_main_activity_type? treats a blank value as Training.
      # Apply the same predicate in SQL before loading JSON records into Ruby.
      .where("COALESCE(LOWER(BTRIM(data::jsonb ->> 'main_activity_type')), '') IN ('', 'training')")
      .order(created_at: :desc)
    if month_name.present?
      records = records.where("LOWER(BTRIM(data::jsonb ->> 'month')) = ?", month_name.to_s.strip.downcase)
    end
    records = training_record_scope_for_farmer_ids(records, farmer_ids) if farmer_ids.any?
    records = records
      .select { |record| training_record_countable?(record) }
      .select { |record| module_record_visible_for_current_context?(record) }
      .select { |record| training_record_main_activity_type?(record) }
      .select { |record| training_record_selected_farmer_ids(record).any? }
      .select { |record| month_name.blank? || normalize_dashboard_text(training_record_month_name(record)) == normalize_dashboard_text(month_name) }
      .select { |record| main_activity_name.blank? || normalize_dashboard_text(training_summary(record)[:training_topic]) == normalize_dashboard_text(main_activity_name) }
      .select { |record| sub_activity_name.blank? || normalize_dashboard_text(training_summary(record)[:training_subject]) == normalize_dashboard_text(sub_activity_name) }
      .select { |record| fcoc_name.blank? || training_record_matches_fcoc?(record, fcoc_name) }

    if vrp_login_user?
      vrp = current_vrp_record
      records = vrp ? records.select { |record| training_record_matches_vrp?(record, vrp) } : []
    end

    if @filtered_vrps.present?
      records = records.select do |record|
        @filtered_vrps.any? { |vrp| training_record_matches_vrp?(record, vrp) }
      end
    end

    preload_training_target_mappings_for_records!(records)
    @dashboard_training_participation_records_cache[cache_key] = records
  end

  def cached_training_participation_dashboard_counts(month_name:, fcoc_name:, week_number: nil)
    cache_key = training_participation_dashboard_counts_cache_key(month_name: month_name, fcoc_name: fcoc_name, week_number: week_number)
    return training_participation_dashboard_counts_uncached(month_name: month_name, fcoc_name: fcoc_name, week_number: week_number) if cache_key.blank?

    DashboardCacheFill.synchronize(cache_key) do
      Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
        training_participation_dashboard_counts_uncached(month_name: month_name, fcoc_name: fcoc_name, week_number: week_number)
      end
    end
  end

  def training_participation_dashboard_counts_uncached(month_name:, fcoc_name:, week_number: nil)
    participation_targets = training_participation_targets_for_dashboard(month_name: month_name, fcoc_name: fcoc_name)
    if week_number.blank?
      sql_counts = training_participation_dashboard_counts_from_sql(month_name: month_name, fcoc_name: fcoc_name, targets: participation_targets)
      return sql_counts if sql_counts.present?
    end

    participation_records = dashboard_training_participation_records(month_name: month_name, fcoc_name: fcoc_name)
    participation_records = participation_records.select { |record| training_record_week_number(record) == week_number.to_i } if week_number.present?
    participation_targets = training_participation_targets_for_week(participation_targets, week_number) if week_number.present?
    training_participation_dashboard_counts(
      month_name: month_name,
      fcoc_name: fcoc_name,
      records: participation_records,
      targets: participation_targets,
      week_number: week_number
    )
  end

  def training_participation_dashboard_counts_cache_key(month_name:, fcoc_name:, week_number: nil)
    return unless model_ready?(:TargetMapping) && model_ready?(:ModuleRecord)

    scope_signature = [
      current_app_user&.dig("record_type"),
      current_app_user&.dig("id"),
      current_app_user&.dig("username"),
      admin_dashboard_user?,
      vrp_login_user?,
      module_mapped_vrp_scope_active? ? module_cluster_visible_vrp_id_strings.sort.join(",") : nil
    ].join(":")
    if dashboard_agronomist_all_months?
      scope_signature += ":fcos:#{dashboard_agronomist_all_month_fcos.sort.join(',')}"
    end
    target_version = dashboard_table_version(TargetMapping)
    training_version = dashboard_module_record_version("training-form")
    afl_version = dashboard_table_version(Afl)
    vrp_version = dashboard_table_version(Vrp)

    [
      dashboard_agronomist_all_months? ? "dashboard/training-participation-counts/agronomist-fco-v1" : "jj-dashboard/training-participation-counts/v3",
      Digest::SHA256.hexdigest([
        dashboard_current_user_office_keys.sort,
        dashboard_visible_vrp_ids.sort,
        params.permit(:cluster_incharge, :post, :vrp_id, :main_activity, :sub_activity, :activity, :search).to_h
      ].to_json),
      normalize_dashboard_text(dashboard_filter_param(:ics, :ics_name)),
      normalize_dashboard_text(month_name),
      normalize_dashboard_text(fcoc_name),
      week_number.presence,
      scope_signature,
      target_version,
      training_version,
      afl_version,
      vrp_version
    ].join("/")
  rescue StandardError => e
    Rails.logger.warn("Dashboard counts cache key failed: #{e.class} - #{e.message}")
    nil
  end

  def training_participation_dashboard_counts_from_sql(month_name:, fcoc_name:, targets:)
    return nil unless model_ready?(:TargetMapping) && model_ready?(:ModuleRecord)

    target_conditions = ["j.value <> ''"]
    unless dashboard_global_view_user?
      target_conditions << "t.vrp_id IN (#{Vrp.where(id: dashboard_visible_vrp_ids).select(:id).to_sql})"
    end
    target_binds = {}
    if dashboard_filter_param(:ics, :ics_name).present?
      target_conditions << "(LOWER(BTRIM(t.ics_id)) = :participation_ics OR LOWER(BTRIM(t.ics_name)) = :participation_ics)"
      target_binds[:participation_ics] = normalize_dashboard_text(dashboard_filter_param(:ics, :ics_name))
    end


    if month_name.present?
      target_conditions << "LOWER(TRIM(t.month_name)) = :participation_month"
      target_binds[:participation_month] = normalize_dashboard_text(month_name)
    end

    if fcoc_name.present?
      fco_values = training_fcoc_filter_values(fcoc_name)
      target_conditions << "(LOWER(BTRIM(t.fco_name)) IN (:participation_fco_values) OR LOWER(BTRIM(t.fco_id)) IN (:participation_fco_values) OR LOWER(BTRIM(v.fcoc)) IN (:participation_fco_values))"
      target_binds[:participation_fco_values] = fco_values
    end

    if vrp_login_user? && current_vrp_record.present?
      target_conditions << "t.vrp_id = :participation_vrp_id"
      target_binds[:participation_vrp_id] = current_vrp_record.id
    elsif dashboard_agronomics_login? && !dashboard_agronomist_all_months?
      target_conditions << "t.vrp_id IN (:participation_vrp_ids)"
      target_binds[:participation_vrp_ids] = dashboard_registered_vrp_ids_for_current_user
    end

    # training_records conditions: only training-form with main_activity_type='training' and main_activity='farmers'' training'
    training_conditions = [
      "mr.module_slug = 'training-form'",
      "LOWER(TRIM(COALESCE(mr.data::jsonb ->> 'main_activity_type', ''))) = 'training'",
      "(LOWER(TRIM(COALESCE(mr.data::jsonb ->> 'main_activity', ''))) = 'farmers'' training' OR (jsonb_typeof(mr.data::jsonb -> 'main_activity') = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(mr.data::jsonb -> 'main_activity') AS ma(activity) WHERE LOWER(TRIM(ma.activity)) = 'farmers'' training')))"
    ]
    completed_binds = {}
    if month_name.present?
      training_conditions << "LOWER(TRIM(COALESCE(mr.data::jsonb ->> 'month', ''))) = :completed_month"
      completed_binds[:completed_month] = normalize_dashboard_text(month_name)
    end

    creator_ids = dashboard_participation_completion_creator_ids
    if creator_ids.any?
      training_conditions << "COALESCE(mr.data::jsonb ->> 'created_by_id', '') IN (:completed_creator_ids)"
      completed_binds[:completed_creator_ids] = creator_ids
    end

    sql = <<~SQL.squish
      WITH assigned AS MATERIALIZED (
        SELECT DISTINCT
          t.id::text AS target_mapping_id,
          TRIM(j.value) AS afl_id
        FROM target_mappings t
        LEFT JOIN vrps v ON v.id = t.vrp_id
        CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
            ELSE jsonb_build_array(t.afl_ids::jsonb)
          END
        ) AS j(value)
        WHERE #{target_conditions.join(' AND ')}
      ),
      training_records AS (
        SELECT mr.id, mr.data::jsonb AS data
        FROM module_records mr
        WHERE #{training_conditions.join(' AND ')}
      ),
      completed_raw AS (
        SELECT
          TRIM(sf.farmer_id) AS farmer_id,
          TRIM(tm.mapping_id) AS target_mapping_id,
          tr.id AS module_record_id
        FROM training_records tr
        CROSS JOIN LATERAL jsonb_array_elements_text(
          COALESCE(tr.data -> 'selected_farmer_ids', '[]'::jsonb)
        ) AS sf(farmer_id)
        CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(tr.data -> 'target_mapping_ids') = 'array'
              THEN tr.data -> 'target_mapping_ids'
            WHEN NULLIF(TRIM(tr.data ->> 'target_mapping_id'), '') IS NOT NULL
              THEN jsonb_build_array(TRIM(tr.data ->> 'target_mapping_id'))
            ELSE '[]'::jsonb
          END
        ) AS tm(mapping_id)
      ),
      completion_count AS MATERIALIZED (
        SELECT
          farmer_id,
          target_mapping_id,
          COUNT(DISTINCT module_record_id) AS entry_count
        FROM completed_raw
        GROUP BY farmer_id, target_mapping_id
      ),
      farmer_status AS (
        SELECT
          a.afl_id,
          COUNT(DISTINCT a.target_mapping_id) AS assigned_activity,
          COUNT(DISTINCT CASE WHEN cc.entry_count >= 1 THEN a.target_mapping_id END) AS completed_activity,
          MAX(CASE WHEN cc.entry_count > 1 THEN 1 ELSE 0 END) AS has_repeat_training
        FROM assigned a
        LEFT JOIN completion_count cc
          ON cc.farmer_id = a.afl_id
         AND cc.target_mapping_id = a.target_mapping_id
        GROUP BY a.afl_id
      )
      SELECT
        COUNT(*) AS total_mapped_farmer,
        COUNT(*) FILTER (
          WHERE completed_activity > 0
            AND has_repeat_training = 1
        ) AS green_count,
        COUNT(*) FILTER (
          WHERE completed_activity > 0
            AND has_repeat_training = 0
        ) AS yellow_count,
        COUNT(*) FILTER (
          WHERE completed_activity = 0
        ) AS red_count,
        COALESCE(SUM(assigned_activity), 0) AS target_map_total,
        COALESCE(SUM(completed_activity), 0) AS completed_target_map_total
      FROM farmer_status
    SQL

    row = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, target_binds.merge(completed_binds)])
    ).first || {}

    {
      green: row["green_count"].to_i,
      yellow: row["yellow_count"].to_i,
      red: row["red_count"].to_i,
      pending: row["red_count"].to_i,
      completed: row["green_count"].to_i,
      completed_target_map_total: row["completed_target_map_total"].to_i,
      registered_farmer_total: training_registered_afl_farmer_count_for_participation(targets, fcoc_name: fcoc_name),
      total: row["total_mapped_farmer"].to_i,
      target_map_total: row["target_map_total"].to_i
    }
  rescue StandardError => e
    Rails.logger.warn("Dashboard participation SQL counts failed: #{e.class} - #{e.message}")
    nil
  end

  def dashboard_participation_completion_creator_ids
    if vrp_login_user?
      dashboard_current_app_user_ids.map(&:to_s)
    elsif dashboard_agronomics_login? && !dashboard_agronomist_all_months?
      dashboard_registered_vrp_ids_for_current_user.map(&:to_s)
    else
      []
    end
  end

  def training_registered_afl_farmer_count_for_participation(targets, fcoc_name: nil)
    return 0 unless model_ready?(:Afl)

    fco_ids = Array(targets).filter_map { |target| target.fco_id.to_s.strip.presence }.uniq
    fco_names = Array(targets).flat_map do |target|
      training_fcoc_filter_values(
        target.fco_name.to_s.strip.presence,
        target.vrp&.fcoc.to_s.strip.presence
      )
    end.compact_blank.uniq

    if fcoc_name.present?
      selected_values = training_fcoc_filter_values(fcoc_name)
      fco_names = (fco_names + selected_values).compact_blank.uniq
    end

    @training_registered_afl_count_cache ||= {}
    cache_key = [fco_ids.sort.join(","), fco_names.sort.join(",")].join("|")
    return @training_registered_afl_count_cache[cache_key] if @training_registered_afl_count_cache.key?(cache_key)

    scope = dashboard_visible_farmer_scope.where.not(id: nil)
    if fco_ids.any? || fco_names.any?
      conditions = []
      binds = {}
      if fco_ids.any?
        conditions << "afls.fco_id IN (:fco_ids)"
        binds[:fco_ids] = fco_ids
      end
      if fco_names.any?
        conditions << "LOWER(BTRIM(afls.fco)) IN (:fco_names)"
        binds[:fco_names] = fco_names.map { |name| normalize_dashboard_text(name) }.reject(&:blank?).uniq
      end
      scope = scope.where(conditions.join(" OR "), binds)
    end

    @training_registered_afl_count_cache[cache_key] = scope.count(:id)
  end

  def farmer_training_mapped_farmer_count_and_popups(month_name:, fcoc_name:)
    @farmer_training_mapped_farmer_count_and_popups_cache ||= {}
    key = [month_name, fcoc_name]
    return @farmer_training_mapped_farmer_count_and_popups_cache[key] if @farmer_training_mapped_farmer_count_and_popups_cache.key?(key)

    @farmer_training_mapped_farmer_count_and_popups_cache[key] = compute_farmer_training_mapped_farmer_count_and_popups(month_name: month_name, fcoc_name: fcoc_name)
  end

  def compute_farmer_training_mapped_farmer_count_and_popups(month_name:, fcoc_name:)
    selected_month = month_name.presence
    all_months = month_name.blank?
    month_filter_sql = all_months ? "TRUE" : "LOWER(BTRIM(t.month_name)) = :month_name"
    fco_ids = training_fcoc_ids_from_param(fcoc_name)
    fco_filter_sql = "AND LOWER(BTRIM(t.fco_id)) IN (:fco_ids)"

    sql = <<~SQL.squish
      SELECT
          t.fco_id,
          COALESCE(MAX(NULLIF(BTRIM(t.fco_name), '')), t.fco_id) AS fco_name,
          COUNT(DISTINCT v.afl_id) AS farmer_count
      FROM public.target_mappings t
      CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
            ELSE jsonb_build_array(t.afl_ids::jsonb)
          END
      ) AS v(afl_id)
      WHERE #{month_filter_sql}
        #{fco_filter_sql}
      GROUP BY t.fco_id
      ORDER BY t.fco_id;
    SQL

    binds = { fco_ids: fco_ids.map(&:downcase) }
    binds[:month_name] = selected_month.strip.downcase unless all_months
    rows = dashboard_sql_cache.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
    ).to_a

    total_count = rows.sum { |r| r["farmer_count"].to_i }
    popups = format_fco_popups(rows, fco_ids, "farmer_count")

    [total_count, popups]
  rescue StandardError => e
    Rails.logger.warn("Mapped farmer count SQL failed: #{e.message}")
    [0, format_fco_popups([], fco_ids, "farmer_count")]
  end

  def farmer_training_no_training_count_and_popups(month_name:, fcoc_name:)
    @farmer_training_no_training_count_and_popups_cache ||= {}
    key = [month_name, fcoc_name, selected_participation_sql_week]
    return @farmer_training_no_training_count_and_popups_cache[key] if @farmer_training_no_training_count_and_popups_cache.key?(key)

    @farmer_training_no_training_count_and_popups_cache[key] = compute_farmer_training_no_training_count_and_popups(month_name: month_name, fcoc_name: fcoc_name)
  end

  def compute_farmer_training_no_training_count_and_popups(month_name:, fcoc_name:)
    # "All Months" selected: run the simpler all-months red query below instead of
    # silently defaulting to August. Every other (specific-month) path below is
    # unchanged.
    return compute_farmer_training_no_training_count_and_popups_all_months(fcoc_name: fcoc_name) if month_name.blank?

    selected_month = month_name.presence || "August"
    fco_ids = training_fcoc_ids_from_param(fcoc_name)
    fco_values = fco_ids.flat_map { |id| training_fcoc_filter_values(id) }.uniq.map(&:downcase)
    fco_filter_sql = "AND LOWER(BTRIM(a.fco_id)) IN (:fco_ids)"
    fco_filter_t = "AND (LOWER(BTRIM(t.fco_id)) IN (:fco_values) OR LOWER(BTRIM(t.fco_name)) IN (:fco_values))"

    sql = <<~SQL.squish
      WITH august_any_mapping AS (
          SELECT DISTINCT v.afl_id
          FROM public.target_mappings t
          CROSS JOIN LATERAL jsonb_array_elements_text(
              CASE
                WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                ELSE jsonb_build_array(t.afl_ids::jsonb)
              END
          ) AS v(afl_id)
          WHERE LOWER(TRIM(t.month_name)) = :month_name
            #{fco_filter_t}
      ),
      august_training_mapping AS (
          SELECT DISTINCT v.afl_id
          FROM public.target_mappings t
          CROSS JOIN LATERAL jsonb_array_elements_text(
              CASE
                WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                ELSE jsonb_build_array(t.afl_ids::jsonb)
              END
          ) AS v(afl_id)
          WHERE LOWER(TRIM(t.month_name)) = :month_name
            #{fco_filter_t}
            AND LOWER(COALESCE(t.main_activity_name, '')) LIKE '%farmers'' training%'
      ),
      august_training_done AS (
          SELECT DISTINCT sf.farmer_id
          FROM public.module_records mr
          CROSS JOIN LATERAL jsonb_array_elements_text(
              COALESCE(
                  mr.data::jsonb -> 'selected_farmer_ids',
                  '[]'::jsonb
              )
          ) AS sf(farmer_id)
          WHERE mr.module_slug = 'training-form'
            AND LOWER(TRIM(mr.data::jsonb ->> 'month')) = :month_name
            #{training_participation_week_filter_sql(selected_participation_sql_week)}
            AND LOWER(COALESCE(mr.data::jsonb ->> 'main_activity', '')) LIKE '%farmers'' training%'
      )
      SELECT
          a.fco_id,
          COALESCE(MAX(NULLIF(BTRIM(a.fco), '')), a.fco_id) AS fco_name,
          COUNT(DISTINCT a.id) AS total_farmer_count,
          COUNT(DISTINCT CASE WHEN am.afl_id IS NOT NULL THEN a.id END) AS total_mapped_farmer_count,
          COUNT(DISTINCT CASE WHEN am.afl_id IS NULL AND td.farmer_id IS NULL THEN a.id END) AS no_activity_mapping_count,
          COUNT(DISTINCT CASE WHEN am.afl_id IS NOT NULL AND tm.afl_id IS NULL AND td.farmer_id IS NULL THEN a.id END) AS no_training_mapping_count,
          COUNT(DISTINCT CASE WHEN tm.afl_id IS NOT NULL AND td.farmer_id IS NULL THEN a.id END) AS training_mapped_but_no_entry_count,
          COUNT(DISTINCT a.id) FILTER (WHERE td.farmer_id IS NULL) AS red_farmer_count
      FROM public.afls a
      LEFT JOIN august_any_mapping am ON am.afl_id = a.id::text
      LEFT JOIN august_training_mapping tm ON tm.afl_id = a.id::text
      LEFT JOIN august_training_done td ON td.farmer_id = a.id::text
      WHERE 1=1
        #{fco_filter_sql}
      GROUP BY a.fco_id
      ORDER BY a.fco_id;
    SQL

    binds = { month_name: selected_month.strip.downcase, fco_ids: fco_ids.map(&:downcase), fco_values: fco_values }
    rows = dashboard_sql_cache.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
    ).to_a

    total_count = rows.sum { |r| r["red_farmer_count"].to_i }
    popups = format_red_fco_popups(rows, fco_ids)
    details = format_red_fco_details(rows, fco_ids)

    [total_count, popups, details]
  rescue StandardError => e
    Rails.logger.warn("No training count SQL failed: #{e.message}")
    [0, format_fco_popups([], fco_ids, "red_farmer_count"), []]
  end

  # "All Months" red count and its hover breakdown. Same shape as the
  # month-specific query above, with every month filter dropped so mapping and
  # training entries are matched across all months. The FCO filter and the
  # login's own visibility scope still apply, so picking Sausar or Turekela
  # narrows this exactly like it does for a single month.

  def compute_farmer_training_no_training_count_and_popups_all_months(fcoc_name:)
    fco_ids = training_fcoc_ids_from_param(fcoc_name)
    fco_filter_sql = "AND LOWER(BTRIM(a.fco_id)) IN (:fco_ids)"

    sql = <<~SQL.squish
      WITH august_any_mapping AS (
          SELECT DISTINCT t.fco_id, v.afl_id
          FROM public.target_mappings t
          CROSS JOIN LATERAL jsonb_array_elements_text(
              CASE
                WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                ELSE jsonb_build_array(t.afl_ids::jsonb)
              END
          ) AS v(afl_id)
      ),
      august_training_mapping AS (
          SELECT DISTINCT t.fco_id, v.afl_id
          FROM public.target_mappings t
          CROSS JOIN LATERAL jsonb_array_elements_text(
              CASE
                WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                ELSE jsonb_build_array(t.afl_ids::jsonb)
              END
          ) AS v(afl_id)
          WHERE LOWER(COALESCE(t.main_activity_name, '')) LIKE '%farmers'' training%'
      ),
      august_training_done AS (
          SELECT DISTINCT sf.farmer_id
          FROM public.module_records mr
          CROSS JOIN LATERAL jsonb_array_elements_text(
              COALESCE(
                  mr.data::jsonb -> 'selected_farmer_ids',
                  '[]'::jsonb
              )
          ) AS sf(farmer_id)
          WHERE mr.module_slug = 'training-form'
            AND LOWER(COALESCE(mr.data::jsonb ->> 'main_activity', '')) LIKE '%farmers'' training%'
      )
      SELECT
          a.fco_id,
          COALESCE(MAX(NULLIF(BTRIM(a.fco), '')), a.fco_id) AS fco_name,
          COUNT(DISTINCT a.id) AS total_farmer_count,
          COUNT(DISTINCT CASE WHEN am.afl_id IS NOT NULL THEN a.id END) AS total_mapped_farmer_count,
          COUNT(DISTINCT CASE WHEN am.afl_id IS NULL THEN a.id END) AS no_activity_mapping_count,
          COUNT(DISTINCT CASE WHEN am.afl_id IS NOT NULL AND tm.afl_id IS NULL THEN a.id END) AS no_training_mapping_count,
          COUNT(DISTINCT CASE WHEN tm.afl_id IS NOT NULL AND td.farmer_id IS NULL THEN a.id END) AS training_mapped_but_no_entry_count,
          COUNT(DISTINCT CASE WHEN td.farmer_id IS NULL THEN a.id END) AS red_farmer_count
      FROM public.afls a
      LEFT JOIN august_any_mapping am ON am.fco_id = a.fco_id AND am.afl_id = a.id::text
      LEFT JOIN august_training_mapping tm ON tm.fco_id = a.fco_id AND tm.afl_id = a.id::text
      LEFT JOIN august_training_done td ON td.farmer_id = a.id::text
      WHERE 1=1
        #{fco_filter_sql}
      GROUP BY a.fco_id
      ORDER BY a.fco_id;
    SQL

    binds = { fco_ids: fco_ids.map(&:downcase) }
    rows = dashboard_sql_cache.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
    ).to_a

    total_count = rows.sum { |r| r["red_farmer_count"].to_i }
    popups = format_red_fco_popups(rows, fco_ids)
    details = format_red_fco_details(rows, fco_ids)

    [total_count, popups, details]
  rescue StandardError => e
    Rails.logger.warn("No training count (all months) SQL failed: #{e.message}")
    [0, format_fco_popups([], fco_ids, "red_farmer_count"), []]
  end

  def farmer_training_yellow_farmer_count_and_popups(month_name:, fcoc_name:)
    @farmer_training_yellow_farmer_count_and_popups_cache ||= {}
    key = [month_name, fcoc_name, selected_participation_sql_week]
    return @farmer_training_yellow_farmer_count_and_popups_cache[key] if @farmer_training_yellow_farmer_count_and_popups_cache.key?(key)

    @farmer_training_yellow_farmer_count_and_popups_cache[key] = compute_farmer_training_yellow_farmer_count_and_popups(month_name: month_name, fcoc_name: fcoc_name)
  end

  def compute_farmer_training_yellow_farmer_count_and_popups(month_name:, fcoc_name:)
    rows = farmer_training_attendance_counts_by_fco(month_name: month_name, fcoc_name: fcoc_name)
    [rows.sum { |row| row["yellow_count"].to_i }, format_fco_popups(rows, training_fcoc_ids_from_param(fcoc_name), "yellow_count")]
  end

  def farmer_training_green_farmer_count_and_popups(month_name:, fcoc_name:)
    @farmer_training_green_farmer_count_and_popups_cache ||= {}
    key = [month_name, fcoc_name, selected_participation_sql_week]
    return @farmer_training_green_farmer_count_and_popups_cache[key] if @farmer_training_green_farmer_count_and_popups_cache.key?(key)

    @farmer_training_green_farmer_count_and_popups_cache[key] = compute_farmer_training_green_farmer_count_and_popups(month_name: month_name, fcoc_name: fcoc_name)
  end

  def compute_farmer_training_green_farmer_count_and_popups(month_name:, fcoc_name:)
    rows = farmer_training_attendance_counts_by_fco(month_name: month_name, fcoc_name: fcoc_name)
    [rows.sum { |row| row["green_count"].to_i }, format_fco_popups(rows, training_fcoc_ids_from_param(fcoc_name), "green_count")]
  end

  def farmer_training_attendance_counts_by_fco(month_name:, fcoc_name:)
    @farmer_training_attendance_counts_by_fco ||= {}
    fco_ids = training_fcoc_ids_from_param(fcoc_name).map(&:downcase)
    # "All Months" selected: drop the month filter (and the week filter, which is
    # only meaningful within one month) so yellow/green are computed across every
    # month's training entries, instead of silently defaulting to August.
    all_months = month_name.blank?
    month = all_months ? nil : normalize_dashboard_text(month_name.presence || "August")
    key = [month, fco_ids.sort, all_months ? nil : selected_participation_sql_week]
    return @farmer_training_attendance_counts_by_fco[key] if @farmer_training_attendance_counts_by_fco.key?(key)

    month_filter_sql = all_months ? "" : "AND LOWER(TRIM(mr.data::jsonb ->> 'month')) = :month_name"
    week_filter_sql = all_months ? "" : training_participation_week_filter_sql(selected_participation_sql_week)

    sql = <<~SQL
      WITH attendance AS MATERIALIZED (
        SELECT sf.farmer_id, COUNT(DISTINCT mr.id) AS training_count
        FROM public.module_records mr
        CROSS JOIN LATERAL jsonb_array_elements_text(
          COALESCE(mr.data::jsonb -> 'selected_farmer_ids', '[]'::jsonb)
        ) AS sf(farmer_id)
        WHERE mr.module_slug = 'training-form'
          #{month_filter_sql}
          #{week_filter_sql}
          AND LOWER(COALESCE(mr.data::jsonb ->> 'main_activity', '')) LIKE '%farmers'' training%'
        GROUP BY sf.farmer_id
      )
      SELECT a.fco_id,
        COALESCE(MAX(NULLIF(BTRIM(a.fco), '')), a.fco_id) AS fco_name,
        COUNT(DISTINCT a.id) FILTER (WHERE attendance.training_count = 1) AS yellow_count,
        COUNT(DISTINCT a.id) FILTER (WHERE attendance.training_count > 1) AS green_count
      FROM public.afls a
      JOIN attendance ON attendance.farmer_id = a.id::text
      WHERE LOWER(BTRIM(a.fco_id)) IN (:fco_ids)
      GROUP BY a.fco_id
      ORDER BY a.fco_id
    SQL
    binds = { fco_ids: fco_ids }
    binds[:month_name] = month unless all_months
    @farmer_training_attendance_counts_by_fco[key] = dashboard_sql_cache.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
    ).to_a
  end

  def training_participation_week_filter_sql(week_number)
    week = week_number.to_i
    return "" unless (1..4).include?(week)

    <<~SQL.squish
      AND LEAST(
        ((COALESCE(
            CASE
              WHEN btrim(mr.data::jsonb ->> 'training_date') ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}'
                THEN split_part(btrim(mr.data::jsonb ->> 'training_date'), '/', 1)::int
              WHEN btrim(mr.data::jsonb ->> 'training_date') ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}'
                THEN substring(btrim(mr.data::jsonb ->> 'training_date') from '^[0-9]{4}-[0-9]{1,2}-([0-9]{1,2})')::int
              ELSE NULL
            END,
            EXTRACT(DAY FROM mr.created_at)::int
          ) - 1) / 7) + 1
      , 4) = #{week}
    SQL
  end

  def farmer_training_participation_rows_from_sql(status, month_name:, fcoc_name:, week_number: nil)
    # "All Months" selected: drop the month filter (and the week filter, which
    # only means anything inside one month) so every list below spans all
    # months. Picking a specific month keeps the original behaviour untouched.
    all_months = month_name.blank?
    selected_month = month_name.presence || "August"
    fco_ids = training_fcoc_ids_from_param(fcoc_name)
    week_filter = all_months ? "" : training_participation_week_filter_sql(week_number || selected_participation_sql_week)
    entry_month_filter = all_months ? "" : "AND LOWER(TRIM(mr.data::jsonb ->> 'month')) = :month_name"
    month_label = all_months ? "All Months" : selected_month

    if status.to_s == "green" || status.to_s == "1_plus_trainings" || status.to_s == "more_than_1"
      fco_filter_sql = "AND LOWER(BTRIM(a.fco_id)) IN (:fco_ids)"
      sql = <<~SQL.squish
        WITH training_records AS MATERIALIZED (
            SELECT
                mr.id AS training_id,
                mr.created_at,
                mr.data::jsonb ->> 'training_date' AS training_date,
                mr.data::jsonb ->> 'sub_activity' AS sub_activity,
                mr.data::jsonb ->> 'training_method' AS training_method,
                mr.data::jsonb ->> 'trainer_name' AS trainer_name,
                mr.data::jsonb ->> 'training_register_upload' AS training_register_upload,
                mr.data::jsonb ->> 'training_photo_upload_with_geo_tag' AS training_photo_upload,
                COALESCE(mr.data::jsonb -> 'selected_farmer_ids', '[]'::jsonb) AS farmer_ids
            FROM public.module_records mr
            WHERE mr.module_slug = 'training-form'
              #{entry_month_filter}
              AND LOWER(COALESCE(mr.data::jsonb ->> 'main_activity', '')) LIKE '%farmers'' training%'
              #{week_filter}
        ), august_training AS (
            SELECT sf.farmer_id, tr.training_id, tr.created_at,
                tr.training_date, tr.sub_activity, tr.training_method,
                tr.trainer_name, tr.training_register_upload, tr.training_photo_upload
            FROM training_records tr
            CROSS JOIN LATERAL jsonb_array_elements_text(tr.farmer_ids) AS sf(farmer_id)
        )
        SELECT
            a.id AS farmer_id,
            a.fco_id,
            a.fco,
            a.fpo_id,
            a.fpo_name,
            a.ics_id,
            a.ics_name,
            a.village_id,
            a.village_name,
            a.tracenet_no,
            a.farmer_name,
            a.father_name,
            a.mobile_no,
            COUNT(DISTINCT at.training_id) AS training_count,
            MIN(at.training_date) AS training_date,
            MIN(at.sub_activity) AS sub_activity,
            STRING_AGG(DISTINCT NULLIF(BTRIM(at.training_method), ''), ', ') AS training_method,
            MIN(at.trainer_name) AS trainer_name,
            STRING_AGG(DISTINCT NULLIF(BTRIM(at.training_register_upload), ''), ', ') AS training_register_urls,
            STRING_AGG(DISTINCT NULLIF(BTRIM(at.training_photo_upload), ''), ', ') AS training_photo_urls
        FROM august_training at
        INNER JOIN public.afls a
            ON a.id::text = at.farmer_id
        WHERE LOWER(BTRIM(a.fco_id)) IN (:fco_ids)
        GROUP BY
            a.id,
            a.fco_id,
            a.fco,
            a.fpo_id,
            a.fpo_name,
            a.ics_id,
            a.ics_name,
            a.village_id,
            a.village_name,
            a.tracenet_no,
            a.farmer_name,
            a.father_name,
            a.mobile_no
        HAVING COUNT(DISTINCT at.training_id) > 1
        ORDER BY
            a.fco_id,
            a.village_name,
            a.farmer_name;
      SQL

      binds = { fco_ids: fco_ids.map(&:downcase) }
      binds[:month_name] = selected_month.strip.downcase unless all_months
      raw_rows = ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
      )

      return raw_rows.map do |row|
        {
          farmer_id: row["farmer_id"].to_s,
          farmer_name: row["farmer_name"].to_s.presence || "Farmer ##{row['farmer_id']}",
          father_name: row["father_name"].to_s,
          mobile_no: row["mobile_no"].to_s,
          tracenet_no: row["tracenet_no"].to_s,
          ics: row["ics_name"].to_s.presence || row["ics_id"].to_s.presence || "-",
          village: row["village_name"].to_s.presence || row["village_id"].to_s.presence || "-",
          fcoc: row["fco"].to_s.presence || row["fco_id"].to_s.presence || "-",
          cluster_incharge: "-",
          jeevika_jankar_name: row["trainer_name"].to_s.presence || "-",
          vrp: row["trainer_name"].to_s.presence || "-",
          registered_by: row["trainer_name"].to_s.presence || "-",
          months: month_label,
          main_activities: "Farmers' Training",
          sub_activities: row["sub_activity"].to_s.presence || "-",
          training_method: row["training_method"].to_s.presence || "-",
          attendance_count: row["training_count"].to_i,
          status: "green",
          status_label: "1+ Trainings",
          training_dates: row["training_date"].to_s.presence || "-",
          last_training_date: row["training_date"].to_s.presence || "-",
          training_register_urls: module_upload_public_urls(row["training_register_urls"]),
          training_photo_urls: module_upload_public_urls(row["training_photo_urls"])
        }
      end
    end

    if status.to_s == "yellow" || status.to_s == "only_1_training"
      sql = <<~SQL.squish
        WITH training_records AS MATERIALIZED (
            SELECT
                mr.id AS training_id,
                mr.created_at,
                mr.data::jsonb ->> 'training_date' AS training_date,
                mr.data::jsonb ->> 'sub_activity' AS sub_activity,
                mr.data::jsonb ->> 'training_method' AS training_method,
                mr.data::jsonb ->> 'trainer_name' AS trainer_name,
                mr.data::jsonb ->> 'training_register_upload' AS training_register_upload,
                mr.data::jsonb ->> 'training_photo_upload_with_geo_tag' AS training_photo_upload,
                COALESCE(mr.data::jsonb -> 'selected_farmer_ids', '[]'::jsonb) AS farmer_ids
            FROM public.module_records mr
            WHERE mr.module_slug = 'training-form'
              #{entry_month_filter}
              AND LOWER(COALESCE(mr.data::jsonb ->> 'main_activity', '')) LIKE '%farmers'' training%'
              #{week_filter}
        ), august_training AS (
            SELECT sf.farmer_id, tr.training_id, tr.created_at,
                tr.training_date, tr.sub_activity, tr.training_method,
                tr.trainer_name, tr.training_register_upload, tr.training_photo_upload
            FROM training_records tr
            CROSS JOIN LATERAL jsonb_array_elements_text(tr.farmer_ids) AS sf(farmer_id)
        )
        SELECT
            a.id AS farmer_id,
            a.fco_id,
            a.fco,
            a.fpo_id,
            a.fpo_name,
            a.ics_id,
            a.ics_name,
            a.village_id,
            a.village_name,
            a.tracenet_no,
            a.farmer_name,
            a.father_name,
            a.mobile_no,
            COUNT(at.training_id) AS training_count,
            MIN(at.training_date) AS training_date,
            MIN(at.sub_activity) AS sub_activity,
            STRING_AGG(DISTINCT NULLIF(BTRIM(at.training_method), ''), ', ') AS training_method,
            MIN(at.trainer_name) AS trainer_name,
            STRING_AGG(DISTINCT NULLIF(BTRIM(at.training_register_upload), ''), ', ') AS training_register_urls,
            STRING_AGG(DISTINCT NULLIF(BTRIM(at.training_photo_upload), ''), ', ') AS training_photo_urls
        FROM august_training at
        INNER JOIN public.afls a
            ON a.id::text = at.farmer_id
        WHERE LOWER(BTRIM(a.fco_id)) IN (:fco_ids)
        GROUP BY
            a.id,
            a.fco_id,
            a.fco,
            a.fpo_id,
            a.fpo_name,
            a.ics_id,
            a.ics_name,
            a.village_id,
            a.village_name,
            a.tracenet_no,
            a.farmer_name,
            a.father_name,
            a.mobile_no
        HAVING COUNT(at.training_id) = 1
        ORDER BY
            a.fco_id,
            a.village_name,
            a.farmer_name;
      SQL

      binds = { fco_ids: fco_ids.map(&:downcase) }
      binds[:month_name] = selected_month.strip.downcase unless all_months
      raw_rows = ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
      )

      return raw_rows.map do |row|
        {
          farmer_id: row["farmer_id"].to_s,
          farmer_name: row["farmer_name"].to_s.presence || "Farmer ##{row['farmer_id']}",
          father_name: row["father_name"].to_s,
          mobile_no: row["mobile_no"].to_s,
          tracenet_no: row["tracenet_no"].to_s,
          ics: row["ics_name"].to_s.presence || row["ics_id"].to_s.presence || "-",
          village: row["village_name"].to_s.presence || row["village_id"].to_s.presence || "-",
          fcoc: row["fco"].to_s.presence || row["fco_id"].to_s.presence || "-",
          cluster_incharge: "-",
          jeevika_jankar_name: row["trainer_name"].to_s.presence || "-",
          vrp: row["trainer_name"].to_s.presence || "-",
          registered_by: row["trainer_name"].to_s.presence || "-",
          months: month_label,
          main_activities: "Farmers' Training",
          sub_activities: row["sub_activity"].to_s.presence || "-",
          training_method: row["training_method"].to_s.presence || "-",
          attendance_count: row["training_count"].to_i,
          status: "yellow",
          status_label: "Only 1 Training",
          training_dates: row["training_date"].to_s.presence || "-",
          last_training_date: row["training_date"].to_s.presence || "-",
          training_register_urls: module_upload_public_urls(row["training_register_urls"]),
          training_photo_urls: module_upload_public_urls(row["training_photo_urls"])
        }
      end
    end

    fco_filter_t  = "AND t.fco_id IN (:fco_ids)"
    fco_filter_a  = "AND a.fco_id IN (:fco_ids)"

    sql = case status.to_s
    when "unique", "mapped"
      Rails.root.join("app/queries/mapped_farmer_details.sql").read
    when "no_activity"
      <<~SQL.squish
        WITH august_any_mapping AS (
            SELECT DISTINCT v.afl_id
            FROM public.target_mappings t
            CROSS JOIN LATERAL jsonb_array_elements_text(
                CASE
                  WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                  ELSE jsonb_build_array(t.afl_ids::jsonb)
                END
            ) AS v(afl_id)
            WHERE %{target_month_filter}
              #{fco_filter_t}
        )
        SELECT a.id, a.fco_id, a.fco, a.fpo_id, a.fpo_name, a.ics_id, a.ics_name, a.village_id, a.village_name, a.tracenet_no, a.farmer_name, a.father_name, a.mobile_no
        FROM public.afls a
        LEFT JOIN august_any_mapping am ON am.afl_id = a.id::text
        WHERE am.afl_id IS NULL #{fco_filter_a}
        ORDER BY a.fco_id, a.id;
      SQL
    when "no_training_mapping", "no_training"
      <<~SQL.squish
        WITH august_any_mapping AS (
            SELECT DISTINCT v.afl_id
            FROM public.target_mappings t
            CROSS JOIN LATERAL jsonb_array_elements_text(
                CASE
                  WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                  ELSE jsonb_build_array(t.afl_ids::jsonb)
                END
            ) AS v(afl_id)
            WHERE %{target_month_filter}
              #{fco_filter_t}
        ),
        august_training_mapping AS (
            SELECT DISTINCT v.afl_id
            FROM public.target_mappings t
            CROSS JOIN LATERAL jsonb_array_elements_text(
                CASE
                  WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                  ELSE jsonb_build_array(t.afl_ids::jsonb)
                END
            ) AS v(afl_id)
            WHERE %{target_month_filter}
              #{fco_filter_t}
              AND LOWER(COALESCE(t.main_activity_name, '')) LIKE '%farmers'' training%'
        )
        SELECT a.id, a.fco_id, a.fco, a.fpo_id, a.fpo_name, a.ics_id, a.ics_name, a.village_id, a.village_name, a.tracenet_no, a.farmer_name, a.father_name, a.mobile_no
        FROM public.afls a
        INNER JOIN august_any_mapping am ON am.afl_id = a.id::text
        LEFT JOIN august_training_mapping tm ON tm.afl_id = a.id::text
        WHERE tm.afl_id IS NULL #{fco_filter_a}
        ORDER BY a.fco_id, a.id;
      SQL
    when "training_mapped_no_entry", "no_entry"
      <<~SQL.squish
        WITH august_training_mapping AS (
            SELECT DISTINCT v.afl_id
            FROM public.target_mappings t
            CROSS JOIN LATERAL jsonb_array_elements_text(
                CASE
                  WHEN jsonb_typeof(t.afl_ids::jsonb) = 'array' THEN t.afl_ids::jsonb
                  ELSE jsonb_build_array(t.afl_ids::jsonb)
                END
            ) AS v(afl_id)
            WHERE %{target_month_filter}
              #{fco_filter_t}
              AND LOWER(COALESCE(t.main_activity_name, '')) LIKE '%farmers'' training%'
        ),
        august_training_done AS (
            SELECT DISTINCT sf.farmer_id
            FROM public.module_records mr
            CROSS JOIN LATERAL jsonb_array_elements_text(
                COALESCE(
                    mr.data::jsonb -> 'selected_farmer_ids',
                    '[]'::jsonb
                )
            ) AS sf(farmer_id)
            WHERE mr.module_slug = 'training-form'
              AND %{entry_month_filter}
              AND LOWER(COALESCE(mr.data::jsonb ->> 'main_activity', '')) LIKE '%farmers'' training%'
        )
        SELECT a.id, a.fco_id, a.fco, a.fpo_id, a.fpo_name, a.ics_id, a.ics_name, a.village_id, a.village_name, a.tracenet_no, a.farmer_name, a.father_name, a.mobile_no
        FROM public.afls a
        INNER JOIN august_training_mapping tm ON tm.afl_id = a.id::text
        LEFT JOIN august_training_done td ON td.farmer_id = a.id::text
        WHERE td.farmer_id IS NULL #{fco_filter_a}
        ORDER BY a.fco_id, a.id;
      SQL
    else # "red", "total_red", "pending"
      Rails.root.join("app/queries/no_training_farmer_details.sql").read
    end

    # Lists and popup breakdowns share the same all-month predicates while
    # dashboard_scoped_training_sql retains the login's authorized scope.
    use_all_month_predicates = all_months
    month_predicates = {
      "target_month_filter" => use_all_month_predicates ? "TRUE" : "LOWER(TRIM(t.month_name)) = :month_name",
      "entry_month_filter" => use_all_month_predicates ? "TRUE" : "LOWER(TRIM(mr.data::jsonb ->> 'month')) = :month_name"
    }
    sql = sql.gsub(/%\{(\w+)\}/) { month_predicates.fetch(Regexp.last_match(1)) }
    sql = sql.gsub("WHERE mr.module_slug = 'training-form'", "WHERE mr.module_slug = 'training-form' #{week_filter}")

    if %w[unique mapped red pending total_red].include?(status.to_s)
      # dashboard_scoped_training_sql already injects the authorised farmer scope.
      # Do not materialise that scope into a large Ruby ID array: on big FCOs it
      # produces a massive IN clause and was responsible for 9–13 second list spikes.
      scoped_sql = dashboard_scoped_training_sql(sql).gsub(" AND a.id IN (:visible_farmer_ids)", "")
      binds = { month_name: selected_month.strip.downcase, fco_ids: fco_ids }
      @mapped_farmer_details = ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.send(:sanitize_sql_array, [scoped_sql, binds])
      )
      return @mapped_farmer_details.map do |row|
        { farmer_id: row["id"].to_s, farmer_name: row["farmer_name"], father_name: row["father_name"],
          mobile_no: row["mobile_no"], tracenet_no: row["tracenet_no"], ics: row["ics_name"],
          village: row["village_name"], fcoc: row["fco"], cluster_incharge: row["cluster_incharge"],
          vrp: row["vrp_name"], months: month_label, status_label: row["status"],
          training_register_urls: module_upload_public_urls(row["training_register_urls"]),
          training_photo_urls: module_upload_public_urls(row["training_photo_urls"]) }
      end
    end

    binds = { month_name: selected_month.strip.downcase, fco_ids: fco_ids.flat_map { |id| [id.to_s, id.to_s.downcase] }.uniq }
    raw_rows = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [dashboard_scoped_training_sql(sql), binds])
    )

    raw_rows.map do |row|
      {
        farmer_id: row["id"].to_s,
        farmer_name: row["farmer_name"].to_s.presence || "Farmer ##{row['id']}",
        father_name: row["father_name"].to_s,
        mobile_no: row["mobile_no"].to_s,
        tracenet_no: row["tracenet_no"].to_s,
        ics: row["ics_name"].to_s.presence || row["ics_id"].to_s.presence || "-",
        village: row["village_name"].to_s.presence || row["village_id"].to_s.presence || "-",
        fcoc: row["fco"].to_s.presence || row["fco_id"].to_s.presence || "-",
        cluster_incharge: "-",
        jeevika_jankar_name: "-",
        vrp: "-",
        registered_by: "-",
        months: month_label,
        main_activities: "Farmers' Training",
        sub_activities: "-",
        attendance_count: 0,
        status: status.to_s,
        status_label: training_participation_status_label(status),
        training_dates: "-",
        last_training_date: "-",
        training_register_urls: [],
        training_photo_urls: []
      }
    end
  rescue StandardError => e
    Rails.logger.warn("Farmer training participation rows SQL failed: #{e.message}")
    []
  end

  # Enrich display fields only. SQL remains authoritative for list membership,
  # attendance counts and statuses. Index once instead of querying per farmer.

  def enrich_training_participation_list_rows!(rows, records, targets)
    rows_by_farmer = Array(rows).group_by { |row| row[:farmer_id].to_s }
    coordinators = Hash.new { |hash, id| hash[id] = [] }
    vrp_ids = Array(records).flat_map { |record| record.data.values_at("jeevika_jankar_id", "vrp_id", "select_vrp") }
      .map(&:to_s).select { |id| id.match?(/\A\d+\z/) }.uniq
    vrp_coordinators = vrp_ids.empty? ? {} : Vrp.where(id: vrp_ids).pluck(:id, :cluster_incharge).to_h.transform_keys(&:to_s)
    Array(targets).each do |target|
      name = target.vrp&.cluster_incharge.to_s.strip
      next if name.blank?

      Array(target.afl_ids).each { |id| coordinators[id.to_s] |= [name] if rows_by_farmer.key?(id.to_s) }
    end
    Array(records).each do |record|
      ids = training_record_selected_farmer_ids(record).select { |id| rows_by_farmer.key?(id.to_s) }
      next if ids.empty?

      name = record.data["cluster_incharge"].presence || record.data["cluster_coordinator"]
      name ||= record.data.values_at("jeevika_jankar_id", "vrp_id", "select_vrp")
        .filter_map { |id| vrp_coordinators[id.to_s].presence }.first
      registers = module_upload_public_urls(record.data["training_register_upload"])
      photos = module_upload_public_urls(record.data["training_photo_upload_with_geo_tag"])
      ids.each do |id|
        coordinators[id.to_s] |= [name.to_s.strip] if name.present?
        rows_by_farmer[id.to_s].each do |row|
          row[:training_register_urls] = Array(row[:training_register_urls]) | registers
          row[:training_photo_urls] = Array(row[:training_photo_urls]) | photos
        end
      end
    end
    Array(rows).each do |row|
      names = coordinators[row[:farmer_id].to_s]
      existing = row[:cluster_incharge].to_s.strip
      names = [existing] | names if existing.present? && existing != "-"
      row[:cluster_incharge] = names.presence&.join(", ") || "-"
    end
  end

  def training_participation_search_match?(values)
    Array(values).flatten.join(" ").downcase.include?(@training_participation_search.downcase)
  end

  def training_participation_dashboard_status_cards(counts, month_name:, fcoc_name:, week_number: nil)
    %w[red yellow green].map do |status|
      path_params = { status: status, ics: dashboard_filter_param(:ics, :ics_name) }.compact_blank
      path_params[:training_month] = month_name if month_name.present?
      path_params[:training_month] = "all" if month_name.blank? && dashboard_agronomist_all_months?
      path_params[:training_fcoc] = fcoc_name if fcoc_name.present?
      path_params[:week] = week_number if week_number.present?
      {
        status: status,
        title: status == "red" ? "Pending" : training_participation_status_label(status),
        value: counts[status.to_sym].to_i,
        caption: status == "red" ? "Selected period mein koi training entry nahi hui." : training_participation_status_caption(status),
        path: farmer_training_participation_path(path_params)
      }
    end
  end

  def training_participation_status_cards(targets, month_name: nil, sub_activity_name: nil, fcoc_name: nil)
    counts = training_participation_status_counts(targets, month_name: month_name)

    %w[red yellow green].map do |status|
      path_params = { status: status }
      path_params[:training_month] = month_name if month_name.present?
      path_params[:training_sub_activity] = sub_activity_name if sub_activity_name.present?
      path_params[:training_fcoc] = fcoc_name if fcoc_name.present?

      {
        status: status,
        title: training_participation_status_label(status),
        value: counts[status.to_sym].to_i,
        caption: training_participation_status_caption(status),
        path: farmer_training_participation_path(path_params)
      }
    end
  end

  def training_participation_status_cards_from_records(records, month_name: nil, sub_activity_name: nil, fcoc_name: nil, population_rows: nil)
    counts = training_participation_status_counts_from_records(records)
    population_counts = population_rows.nil? ? {} : training_participation_status_counts_from_rows(population_rows)

    %w[red yellow green].map do |status|
      path_params = { status: status }
      path_params[:training_month] = month_name if month_name.present?
      path_params[:training_sub_activity] = sub_activity_name if sub_activity_name.present?
      path_params[:training_fcoc] = fcoc_name if fcoc_name.present?

      {
        status: status,
        title: training_participation_status_label(status),
        value: population_counts.fetch(status.to_sym, counts[status.to_sym]).to_i,
        caption: training_participation_status_caption(status),
        path: farmer_training_participation_path(path_params)
      }
    end
  end

  def training_participation_status_label(status)
    {
      "total" => "Multiple Total Target Map",
      "unique" => "Mapped Farmer",
      "no_activity" => "No Activity Mapping",
      "no_training_mapping" => "No Training Mapping",
      "no_training" => "No Training Mapping",
      "training_mapped_no_entry" => "Training Mapped But No Entry",
      "no_entry" => "Training Mapped But No Entry",
      "training_unique" => "Total Complete Farmers",
      "completed_map" => "Multiple Total Complete Training",
      "green" => "1+ Trainings",
      "yellow" => "Only 1 Training",
      "red" => "Pending",
      "pending" => "Pending",
      "pending_achievement" => "Pending Achievement",
      "completed" => "Completed"
    }[status.to_s] || "Farmer"
  end

  def dashboard_user_label_match_values(label)
    @dashboard_user_label_match_values_cache ||= {}
    @dashboard_user_label_match_values_cache[label.to_s] ||= begin
      normalized = normalize_dashboard_user_label(label)
      base = normalize_dashboard_user_label(label.to_s.sub(/\s*\([^)]*\)\s*\z/, ""))

      [normalized, base].compact_blank.reject { |value| value.length < 3 }.uniq
    end
  end

  def dashboard_filter_param(*keys)
    return nil if request.nil? && @_params.nil?

    @dashboard_filter_param_cache ||= {}
    cache_key = keys.map(&:to_s)
    return @dashboard_filter_param_cache[cache_key] if @dashboard_filter_param_cache.key?(cache_key)

    keys.each do |key|
      value = params[key].to_s.strip
      next if dashboard_all_filter_value?(value)

      return @dashboard_filter_param_cache[cache_key] = value if value.present?
    end
    @dashboard_filter_param_cache[cache_key] = nil
  end

  def dashboard_all_filter_value?(value)
    normalized = value.to_s.strip.downcase
    normalized.blank? || normalized == "all" || normalized.start_with?("all ")
  end

  # All Months rolls up the agronomist's assigned FCOs, including farmers
  # without target mappings. Never derive authorization from the selected FCO.

  def dashboard_ics_filtered_scope(scope)
    ics = dashboard_filter_param(:ics, :ics_name)
    return scope if ics.blank?

    scope.where("LOWER(BTRIM(ics_id)) = :ics OR LOWER(BTRIM(ics_name)) = :ics", ics: normalize_dashboard_text(ics))
  end

  def selected_participation_sql_week
    value = dashboard_filter_param(:week, :weekly_target_week).to_i
    (1..4).include?(value) ? value : nil
  end

  def bill_summary_scope(base)
    base.select(<<~SQL.squish)
      module_records.id, module_records.module_slug,
      module_records.created_at, module_records.updated_at,
      CASE
        WHEN jsonb_typeof(module_records.data::jsonb -> 'bill_items') = 'array'
        THEN jsonb_set(
               module_records.data::jsonb, '{bill_items}',
               COALESCE((
                 SELECT jsonb_agg(elem - 'farmer_details' ORDER BY ord)
                 FROM jsonb_array_elements(module_records.data::jsonb -> 'bill_items')
                   WITH ORDINALITY AS t(elem, ord)
               ), '[]'::jsonb)
             )::text
        ELSE module_records.data
      END AS data
    SQL
  end

  public :cc_target_status_list, :farmer_training_participation, :dashboard, :demonstration_method_farmers
  private

  # Scope every dashboard query before applying user-controlled filters.
  def dashboard_vrps
    return @dashboard_vrps if defined?(@dashboard_vrps)
    return @dashboard_vrps = [] unless model_ready?(:Vrp)
    return @dashboard_vrps = Vrp.all.to_a if dashboard_global_view_user?
    return @dashboard_vrps = [current_vrp_record].compact if vrp_login_user?
    if module_cluster_incharge_login?
      return @dashboard_vrps = module_cluster_visible_vrps
    end
    offices = dashboard_current_user_office_keys
    @dashboard_vrps = offices.any? ? Vrp.all.select { |vrp| offices.include?(AgreementVrpScope.office_key(vrp.fcoc)) } : []
  end

  def dashboard_target_mappings
    @dashboard_target_mappings ||= dashboard_visible_target_scope.includes(:vrp).order(updated_at: :desc).to_a
  end

  def dashboard_visible_target_scope
    scope = dashboard_global_view_user? ? TargetMapping.all : TargetMapping.where(vrp_id: dashboard_visible_vrp_ids)
    cluster = dashboard_filter_param(:cluster_incharge)
    post = dashboard_filter_param(:post)
    selected = dashboard_filter_param(:vrp_id)
    if cluster.present? || post.present? || selected.present?
      ids = dashboard_vrps.select do |vrp|
        (cluster.blank? || cluster_label_matches?(cluster, vrp.cluster_incharge)) &&
          (post.blank? || vrp.role.to_s == post) &&
          (selected.blank? || vrp.id.to_s == selected)
      end.map(&:id)
      scope = scope.where(vrp_id: ids)
    end
    dashboard_ics_filtered_scope(scope)
  end

  def dashboard_user_visible_farmer_scope
    specific_jj_scope = dashboard_filter_param(:cluster_incharge, :post, :vrp_id).present?
    return Afl.all if dashboard_global_view_user? && !specific_jj_scope
    unless module_cluster_incharge_login? || vrp_login_user? || specific_jj_scope
      ids = dashboard_afl_fco_ids_for(dashboard_current_user_office_names)
      return Afl.where(fco_id: ids)
    end
    target_sql = dashboard_visible_target_scope.select(:afl_ids).to_sql
    Afl.where("afls.id::text IN (SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(visible_targets.afl_ids::jsonb) = 'array' THEN visible_targets.afl_ids::jsonb ELSE '[]'::jsonb END) FROM (#{target_sql}) visible_targets)")
  end

  def dashboard_visible_farmer_scope
    dashboard_ics_filtered_scope(dashboard_user_visible_farmer_scope)
  end

  def dashboard_scoped_training_sql(sql)
    sql.gsub("public.target_mappings", "(#{dashboard_visible_target_scope.to_sql})")
      .gsub("public.afls", "(#{dashboard_visible_farmer_scope.to_sql})")
  end

  def dashboard_current_user_office_names
    names = super
    roles = %w[role role_name stakeholder_role user_management_role person_type].filter_map do |key|
      value = current_app_user&.dig(key).to_s
      value if value.match?(/\Afco(?:c|[-\s]|\z)/i)
    end
    (names + roles).uniq
  end

  def dashboard_current_user_office_keys
    @dashboard_current_user_office_keys ||= dashboard_current_user_office_names.filter_map { |name| AgreementVrpScope.office_key(name).presence }.uniq
  end

  def dashboard_fco_names
    names = (DashboardFcoDirectory.names + dashboard_vrps.map(&:fcoc) +
      (dashboard_global_view_user? ? [] : dashboard_current_user_office_names))
      .compact_blank.map { |value| DashboardFcoDirectory.bare_name(value) }.uniq.sort
    values = if dashboard_global_view_user?
      selected = dashboard_filter_param(:fcoc, :fco)
      selected.present? ? training_fcoc_filter_values(selected) : []
    else
      visible_values = dashboard_visible_fco_filter_values
      if module_cluster_incharge_login? || vrp_login_user?
        visible_values
      else
        (visible_values + training_fcoc_filter_values(dashboard_current_user_office_names)).uniq
      end
    end
    names = names.select { |name| (training_fcoc_filter_values(name) & values).any? } if values.any?
    return [] if !dashboard_global_view_user? && values.empty?
    names
  end

  def dashboard_summary_fco_filter_values(fcoc_value = nil)
    selected = training_fcoc_filter_values(fcoc_value)
    return selected if selected.any?
    return [] if dashboard_global_view_user?
    module_cluster_incharge_login? || vrp_login_user? ? dashboard_visible_fco_filter_values : training_fcoc_filter_values(dashboard_current_user_office_names)
  end

  def training_fcoc_filter_values(*values)
    (super + values.flatten.compact.map { |value| AgreementVrpScope.office_key(value) }.compact_blank + values.flatten.compact.flat_map { |value| DashboardFcoDirectory.aliases_for(value) }.map { |value| normalize_dashboard_text(value) }).uniq
  end

  def training_fcoc_ids_from_param(value)
    raw_values = Array(value).flat_map { |item| item.to_s.split(",") }.compact_blank
    return DashboardFcoDirectory.ids if raw_values.empty?
    raw_values.flat_map { |name| DashboardFcoDirectory.ids_for(name) }.uniq
  end

  # Agronomists report on their office's JJs, regardless of who registered them.
  def dashboard_registered_vrp_ids_for_current_user
    dashboard_visible_vrp_ids
  end

  def dashboard_agronomist_all_months?
    false
  end

  def dashboard_agronomist_all_month_fcos
    []
  end

  OTHER_INDICATOR_LIST_HEADERS = {
    "Jeevika Jankar" => "jeevika_jankar_name", "FCO Name" => "fco_name",
    "Month" => "month", "ICS Name" => "ics_name",
    "Main Major Work Indicator" => "main_activity", "Sub Major Work Indicator" => "sub_activity",
    "Target" => "target", "Achievement" => "achievement"
  }.freeze

  def dashboard_other_target_entry_rows
    return @dashboard_other_target_entry_rows if defined?(@dashboard_other_target_entry_rows)
    records = active_module_records_scope("other-target")
    month = @dashboard_month_filter_value.presence || dashboard_filter_param(:month, :training_month)
    records = records.where("LOWER(BTRIM(data::jsonb ->> 'month')) = ?", normalize_dashboard_text(month)) if month.present?
    vrps = dashboard_vrps.index_by { |vrp| vrp.id.to_s }
    targets = dashboard_target_mappings.index_by { |target| target.id.to_s }
    names = vrps.values.map { |vrp| normalize_dashboard_text(vrp.name) }.compact_blank
    rows = records.filter_map do |record|
      data = record.data
      target = targets[data["target_mapping_id"].to_s]
      vrp_id = data["jeevika_jankar_id"].presence || data["vrp_id"].presence || data["select_vrp"].presence || target&.vrp_id&.to_s
      next unless dashboard_global_view_user? || vrps.key?(vrp_id.to_s) || (vrp_id.blank? && names.include?(normalize_dashboard_text(data["jeevika_jankar_name"])))
      vrp = vrps[vrp_id.to_s] || target&.vrp
      office = data["fcoc_name"].presence || data["department"].presence || vrp&.fcoc || target&.fco_name
      selected_fco = @dashboard_fcoc_filter_value.presence || dashboard_filter_param(:fcoc, :fco)
      next if selected_fco.present? && !training_fcoc_text_matches?(office, selected_fco)
      ics = data["ics_name"].presence || data["ics"].presence || data["ics_block"].presence || target&.ics_name || target&.ics_id
      selected_ics = dashboard_filter_param(:ics, :ics_name)
      next if selected_ics.present? && ![ics, target&.ics_id].any? { |value| normalize_dashboard_text(value) == normalize_dashboard_text(selected_ics) }
      selected_vrp = dashboard_filter_param(:vrp_id)
      next if selected_vrp.present? && vrp_id.to_s != selected_vrp
      selected_cluster = dashboard_filter_param(:cluster_incharge)
      next if selected_cluster.present? && !cluster_label_matches?(selected_cluster, vrp&.cluster_incharge)
      {
        "jeevika_jankar_name" => data["jeevika_jankar_name"].presence || vrp&.name,
        "fco_name" => office, "month" => data["month"], "ics_name" => ics,
        "main_activity" => Array(data["main_activity"].presence || data["training_topic"].presence || target&.main_activity_name).join(", "),
        "sub_activity" => Array(data["sub_activity"].presence || data["training_subject"].presence || target&.activity_name).join(", "),
        "target" => dashboard_numeric(data["target"]), "achievement" => dashboard_numeric(data["achievement"]),
        "status" => data["approval_status"].presence || data["status"], "target_mapping_id" => data["target_mapping_id"]
      }
    end
    @dashboard_other_target_entry_rows = dashboard_search_rows(rows).sort_by { |row| [row["fco_name"].to_s, row["jeevika_jankar_name"].to_s, row["month"].to_s] }
  end

  def dashboard_search_rows(rows)
    queries = [params[:search], params[:q]].compact_blank.map { |query| query.to_s.strip.downcase }
    rows.select { |row| queries.all? { |query| row.values.flatten.compact.join(" ").downcase.include?(query) } }
  end

  def dashboard_fco_active_vrp_records(fco, month = nil, vrps = nil)
    population = Array(vrps || dashboard_vrps)
    @dashboard_fco_active_vrp_records_cache ||= {}
    key = [AgreementVrpScope.office_key(fco), month, population.map(&:id).sort]
    return @dashboard_fco_active_vrp_records_cache[key] if @dashboard_fco_active_vrp_records_cache.key?(key)
    scope = dashboard_visible_target_scope
    scope = scope.where("LOWER(BTRIM(month_name)) = ?", month.to_s.downcase) if month.present? && !dashboard_all_filter_value?(month)
    values = training_fcoc_filter_values(fco)
    scope = scope.where("LOWER(BTRIM(fco_id)) IN (:values) OR LOWER(BTRIM(fco_name)) IN (:values)", values: values)
    ids = scope.distinct.pluck(:vrp_id)
    ids = ids.to_set
    @dashboard_fco_active_vrp_records_cache[key] = if ids.any?
      population.select { |vrp| ids.include?(vrp.id) }
    else
      population.select { |vrp| training_fcoc_text_matches?(vrp.fcoc, fco) && dashboard_vrp_active_for_requirement?(vrp) }
    end
  end

  def dashboard_fco_active_vrp_count(fco, month = nil, vrps = nil)
    dashboard_fco_active_vrp_records(fco, month, vrps).size
  end

  public

  def report_list
    @dashboard_month_filter_value = params.key?(:month) ? dashboard_filter_param(:month) : DashboardDefaults.month
    @dashboard_fcoc_filter_value = dashboard_filter_param(:fcoc, :fco)
    @dashboard_main_activity_filter_value = dashboard_filter_param(:main_activity)
    @report_type = params[:report_type].to_s
    @report_title, @report_headers, rows = dashboard_report_data(@report_type)
    return head :not_found unless @report_title
    @report_rows = dashboard_search_rows(rows)
    @report_months = (Date::MONTHNAMES.compact + month_master_month_options).uniq
    respond_to do |format|
      format.html { render :report_list }
      format.xlsx do
        send_xlsx(headers: @report_headers, rows: @report_rows.map { |row| @report_headers.map { |header| row[header] } },
          filename: "dashboard-#{@report_type}.xlsx", sheet_name: @report_title)
      end
    end
  end

  private

  def dashboard_report_filter_params
    request.query_parameters.except("format").merge(
      "month" => @dashboard_month_filter_value.to_s,
      "fcoc" => @dashboard_fcoc_filter_value.to_s,
      "main_activity" => @dashboard_main_activity_filter_value.to_s
    )
  end

  def dashboard_summary_cards(targets)
    counts = dashboard_summary_login_counts(targets)
    [
      ["Total ICS Count", :ics_count, "ics"],
      ["Total Villages Count", :village_count, "villages"],
      ["Total Farmer Count", :farmer_count, "farmers"],
      ["Total Mapped Main Activities", :main_activity_count, "main-indicators"],
      ["Total Mapped Sub-Activities", :sub_activity_count, "sub-indicators"]
    ].map do |title, key, type|
      filters = dashboard_report_filter_params
      path = dashboard_report_list_path(type, filters)
      export = dashboard_report_list_path(type, filters.merge(format: :xlsx))
      popup = if type == "main-indicators"
        dashboard_summary_activity_popup_items(:main_activity)
      elsif type == "sub-indicators"
        dashboard_summary_activity_popup_items(:sub_activity)
      end
      dashboard_summary_card(title, counts[key], "Selected login and reporting filters", path, export, popup_items: popup)
    end
  end

  def dashboard_report_data(type)
    case type
    when "ics", "villages", "farmers"
      scope = type == "ics" ? dashboard_total_afl_scope : dashboard_total_afl_farmer_scope
      common = { "FCO ID" => :fco_id, "FCO Name" => :fco, "FPO ID" => :fpo_id, "FPO Name" => :fpo_name, "ICS ID" => :ics_id, "ICS Name" => :ics_name }
      columns = type == "ics" ? common : common.merge("Village ID" => :village_id, "Village Name" => :village_name)
      if type == "farmers"
        columns = columns.merge("TraceNet No" => :tracenet_no, "Farmer Name" => :farmer_name, "Father Name" => :father_name, "Mobile No" => :mobile_no)
        population = scope.where("NULLIF(BTRIM(tracenet_no), '') IS NOT NULL").order(:id).to_a
      else
        key = type == "ics" ? :ics_id : :village_id
        population = scope.where.not(key => [nil, ""]).select(*columns.values).distinct.to_a
      end
      rows = population.map { |farmer| columns.transform_values { |field| farmer.public_send(field) } }
      [type == "ics" ? "ICS List" : type == "villages" ? "Village List" : "Farmer List", columns.keys, rows]
    when "main-indicators", "sub-indicators"
      field = type == "main-indicators" ? :main_activity_name : :activity_name
      title = type == "main-indicators" ? "Main Major Work Indicator" : "Sub Major Work Indicator"
      targets = dashboard_summary_target_scope.includes(:vrp).to_a
      groups = targets.reject { |target| target.public_send(field).blank? }.group_by { |target| normalize_dashboard_text(target.public_send(field)) }
      rows = groups.values.map do |group|
        { title => group.first.public_send(field), "Month" => group.map(&:month_name).compact_blank.uniq.join(", "),
          "FCO Name" => group.map(&:fco_name).compact_blank.uniq.join(", "),
          "ICS Name" => group.filter_map { |target| target.ics_name.presence || target.ics_id.presence }.uniq.join(", "),
          "Jeevika Jankar" => group.filter_map { |target| target.vrp&.name }.uniq.join(", ") }
      end
      [title, [title, "Month", "FCO Name", "ICS Name", "Jeevika Jankar"], rows]
    when "registered", "approved", "pending", "gender-male", "gender-female", "active"
      vrps = dashboard_vrps.select { |vrp| vrp.is_active && !vrp.is_deleted }
      office = @dashboard_fcoc_filter_value
      vrps.select! { |vrp| training_fcoc_text_matches?(vrp.fcoc, office) } if office.present?
      vrps = dashboard_approved_vrps(vrps) if type == "approved"
      vrps = dashboard_pending_approval_vrps(vrps) if type == "pending"
      if type.start_with?("gender-") || type == "active"
        vrps = dashboard_fco_active_vrp_records(office, @dashboard_month_filter_value, vrps)
        vrps.select! { |vrp| normalize_dashboard_text(vrp.gender) == type.delete_prefix("gender-") } if type.start_with?("gender-")
      end
      rows = vrps.map { |vrp| { "Jeevika Jankar" => vrp.name, "FCO Name" => vrp.fcoc, "Cluster Coordinator" => vrp.cluster_incharge, "Gender" => vrp.gender, "Mobile No" => vrp.mobile_no } }
      ["Jeevika Jankar List", ["Jeevika Jankar", "FCO Name", "Cluster Coordinator", "Gender", "Mobile No"], rows]
    when "bill-approved", "bill-pending"
      bills = dashboard_billing_records
      month = @dashboard_month_filter_value
      bills.select! { |bill| normalize_dashboard_text(bill.data["bill_month"].presence || bill.data["select_bill_month"]) == normalize_dashboard_text(month) } if month.present?
      bills.select! { |bill| type == "bill-approved" ? dashboard_bill_approved?(bill) : dashboard_bill_pending?(bill) }
      rows = bills.map { |bill| { "Jeevika Jankar" => bill.data["select_vrp_name"].presence || jeevika_bill_vrp(bill)&.name, "Month" => bill.data["bill_month"], "Status" => bill.data["status"], "Amount" => bill.data["grand_total"] } }
      ["Jeevika Jankar Bills", ["Jeevika Jankar", "Month", "Status", "Amount"], rows]
    when "required", "vacant"
      office = @dashboard_fcoc_filter_value
      items = dashboard_jj_requirement_items(office, dashboard_vrps, dashboard_summary_target_scope.to_a)
      rows = [{ "FCO Name" => office, "Required" => items[0][:value], "Active" => items[1][:value], "Vacant" => items[2][:value] }]
      ["FCO-wise JJ Requirement", ["FCO Name", "Required", "Active", "Vacant"], rows]
    else
      [nil, [], []]
    end
  end

  def dashboard_group_card(title, items, style: nil)
    mapped = items.map do |item|
      type, office = case title
      when "Jeevika Jankar Registration"
        [{ "Total Registered" => "registered", "Final Approved" => "approved", "Pending Approval" => "pending" }[item[:title]], nil]
      when "Jeevika Jankar Billing"
        [item[:title] == "Approved" ? "bill-approved" : "bill-pending", nil]
      when "Gender Count"
        [item[:title].end_with?(" Male") ? "gender-male" : "gender-female", item[:title].sub(/ (Male|Female)\z/, "")]
      when "FCO-wise JJ Requirement"
        [item[:title].split.last.downcase, item[:title].sub(/ (Required|Active|Vacant)\z/, "")]
      end
      next item unless type
      filters = dashboard_report_filter_params
      filters["fcoc"] = office if office.present?
      item.merge(path: dashboard_report_list_path(type, filters))
    end
    { title: title, items: mapped, style: style }
  end

  def dashboard_billing_records
    @dashboard_billing_records ||= begin
      ids = dashboard_vrps.map { |vrp| vrp.id.to_s }
      office = @dashboard_fcoc_filter_value.presence || dashboard_filter_param(:fcoc, :fco)
      if office.present?
        ids = dashboard_vrps.select { |vrp| training_fcoc_text_matches?(vrp.fcoc, office) }.map { |vrp| vrp.id.to_s }
      end
      active_module_records_scope("jeevika-jankar-bill-process").select do |record|
        jeevika_jankar_bill_blocks_duplicate?(record) &&
          ((dashboard_global_view_user? && office.blank?) || ids.include?(record.data["select_vrp"].to_s))
      end
    end
  end

  # Fresh, request-local source revisions avoid both repeated version queries
  # and the old minute-long delay after a target or training entry changes.
  def dashboard_table_version(model_class)
    return super unless DashboardSqlCache::TABLES.include?(model_class.table_name)
    dashboard_sql_cache.source_revision
  end

  def dashboard_module_record_version(_module_slug)
    dashboard_sql_cache.source_revision
  end

  def dashboard_sql_cache
    @dashboard_sql_cache ||= DashboardSqlCache.new
  end

  def dashboard_afl_fco_ids_for(values)
    Array(values).flat_map { |value| DashboardFcoDirectory.ids_for(value) }.uniq
  end

  def dashboard_total_afl_scope
    scope = dashboard_visible_farmer_scope.where.not(id: nil)
    office = @dashboard_fcoc_filter_value.presence || dashboard_filter_param(:fcoc, :fco)
    values = dashboard_summary_fco_filter_values(office)
    if values.any?
      ids = dashboard_afl_fco_ids_for(values)
      scope = ids.any? ? scope.where(fco_id: ids) : scope.none
    end
    scope
  end

  def dashboard_total_afl_farmer_scope
    dashboard_total_afl_scope
  end

end
