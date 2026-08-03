module Api
  module V1
    class JeevikaJankarDashboardController < BaseController
      def show
        return render_admin_dashboard if admin_dashboard_request?

        vrp = current_dashboard_vrp
        return render json: { success: false, message: "Valid Jeevika Jankar login required." }, status: :unprocessable_entity unless vrp

        targets = TargetMapping.where(vrp_id: vrp.id).order(:month_name, :main_activity_name, :activity_name, :id).to_a
        months = targets.filter_map { |target| target.month_name.to_s.strip.presence }.uniq
        selected_month = params[:month].presence || params[:training_month].presence || default_month(months)
        targets = targets.select { |target| same_text?(target.month_name, selected_month) } if selected_month.present?
        progress = web_parity_progress(targets, vrp)
        assigned = progress.sum { |row| row[:assigned].to_f }
        achieved = progress.sum { |row| row[:achieved].to_f }

        render json: {
          success: true,
          message: "Jeevika Jankar dashboard fetched successfully.",
          jeevika_jankar: { id: vrp.id, name: vrp.name, user_name: vrp.user_name, mobile_no: vrp.mobile_no },
          months: months,
          selected_month: selected_month,
          cards: {
            mapped_farmers: targets.flat_map { |target| mapped_farmer_ids(target) }.uniq.size,
            mapped_villages: targets.map { |target| [target.village_id.to_s, target.village_name.to_s.downcase] }.uniq.size,
            main_activities: unique_count(targets, :main_activity_name),
            sub_activities: unique_count(targets, :activity_name),
            assigned_target: number(assigned),
            achieved_target: number(achieved),
            pending_target: number([assigned - achieved, 0].max)
          },
          target_progress: progress,
          generated_at: Time.current.iso8601
        }, status: :ok
      end

      private

      def admin_dashboard_request?
        user = current_api_user_payload
        user["user_type"].to_s.casecmp("admin").zero? && params[:vrp_id].blank?
      end

      def render_admin_dashboard
        vrps = Vrp.where(is_deleted: false).to_a
        targets = TargetMapping.includes(:vrp).order(updated_at: :desc).to_a
        filter_options = admin_filter_options(vrps, targets)
        vrps = filter_admin_vrps(vrps)
        targets = targets.select { |target| vrps.any? { |vrp| vrp.id == target.vrp_id } } if admin_vrp_filters_present?
        filtered_targets = filter_admin_targets(targets)
        selected_month = params[:month].presence
        progress = filtered_targets.map { |target| progress_payload(target) }
        assigned = progress.sum { |row| row[:assigned].to_f }
        achieved = progress.sum { |row| row[:achieved].to_f }
        bills = ModuleRecord.where(module_slug: "vrp-bill-add").select { |record| active_record?(record) }

        render json: {
          success: true,
          message: "Admin dashboard fetched successfully.",
          dashboard_type: "admin",
          filters: admin_filter_payload,
          filter_options: filter_options,
          months: filter_options[:months],
          selected_month: selected_month,
          cards: {
            registered_users: User.count,
            total_registered_jeevika_jankars: vrps.size,
            final_approved_jeevika_jankars: vrps.count { |vrp| vrp.status.to_i == 55 },
            pending_jeevika_jankar_approvals: vrps.count { |vrp| vrp.status.to_i.between?(25, 54) },
            target_records: filtered_targets.size,
            activities_assigned: filtered_targets.map { |target| [target.main_activity_name.to_s.downcase, target.activity_name.to_s.downcase] }.uniq.size,
            mapped_farmers: filtered_targets.flat_map { |target| mapped_farmer_ids(target) }.uniq.size,
            mapped_villages: filtered_targets.map { |target| [target.village_id.to_s, target.village_name.to_s.downcase] }.uniq.size,
            assigned_target: number(assigned),
            achieved_target: number(achieved),
            pending_target: number([assigned - achieved, 0].max),
            bills_approved: bills.count { |bill| approved_bill?(bill) },
            bills_pending: bills.count { |bill| !approved_bill?(bill) }
          },
          monthly_target_summary: monthly_target_summary(targets),
          farmer_training_participation_status: training_participation_status(filtered_targets),
          target_dashboard: target_dashboard_payload(filtered_targets),
          weekly_activity_target_status: weekly_target_status(progress),
          recent_target_progress: progress.first(100),
          generated_at: Time.current.iso8601
        }, status: :ok
      end

      def admin_filter_options(vrps, targets)
        {
          activities: targets.filter_map { |target| target.main_activity_name.to_s.strip.presence }.uniq.sort,
          fcos: vrps.filter_map { |vrp| vrp.fcoc.to_s.strip.presence }.uniq.sort,
          cluster_incharges: vrps.filter_map { |vrp| vrp.cluster_incharge.to_s.strip.presence }.uniq.sort,
          months: targets.filter_map { |target| target.month_name.to_s.strip.presence }.uniq.sort,
          post_wise_names: vrps.filter_map { |vrp| vrp.role.to_s.strip.presence }.uniq.sort,
          jeevika_jankars: vrps.map { |vrp| { id: vrp.id, name: vrp.name, user_name: vrp.user_name } }
        }
      end

      def filter_admin_vrps(vrps)
        vrps.select do |vrp|
          filter_value_matches?(vrp.fcoc, params[:fco]) &&
            filter_value_matches?(vrp.cluster_incharge, params[:cluster_incharge]) &&
            filter_value_matches?(vrp.role, params[:post_wise_name]) &&
            (params[:vrp_id].blank? || vrp.id.to_s == params[:vrp_id].to_s)
        end
      end

      def filter_admin_targets(targets)
        targets.select do |target|
          filter_value_matches?(target.month_name, params[:month]) &&
            filter_value_matches?(target.main_activity_name, params[:activity]) &&
            filter_value_matches?(target.activity_name, params[:sub_activity])
        end
      end

      def admin_vrp_filters_present?
        %i[fco cluster_incharge post_wise_name vrp_id].any? { |key| params[key].present? }
      end

      def admin_filter_payload
        {
          activity: params[:activity],
          fco: params[:fco],
          cluster_incharge: params[:cluster_incharge],
          month: params[:month],
          post_wise_name: params[:post_wise_name],
          vrp_id: params[:vrp_id],
          sub_activity: params[:sub_activity]
        }
      end

      def filter_value_matches?(actual, selected)
        selected.blank? || same_text?(actual, selected)
      end

      def training_participation_status(targets)
        farmer_ids = targets.flat_map { |target| mapped_farmer_ids(target) }.uniq
        attendance = Hash.new(0)
        ModuleRecord.where(module_slug: "training-form").select { |record| active_record?(record) }.each do |record|
          Array(record.data["selected_farmer_ids"]).map(&:to_s).uniq.each { |farmer_id| attendance[farmer_id] += 1 }
        end
        green = farmer_ids.count { |id| attendance[id] >= 3 }
        yellow = farmer_ids.count { |id| attendance[id].between?(1, 2) }
        untrained = farmer_ids.select { |id| attendance[id].zero? }
        closed_target = targets.any? { |target| target.completion_date.present? && target.completion_date < Date.current }
        red = closed_target ? untrained.size : 0
        pending = closed_target ? 0 : untrained.size
        { total_training_farmers: farmer_ids.size, green: green, yellow: yellow, red: red, pending: pending }
      end

      def target_dashboard_payload(targets)
        sub_activities = targets.filter_map { |target| target.activity_name.to_s.strip.presence }.uniq.sort
        {
          selected_month: params[:month],
          selected_sub_activity: params[:sub_activity],
          sub_activity_options: sub_activities,
          rows: targets.map { |target| progress_payload(target) }
        }
      end

      def weekly_target_status(progress)
        percentages = progress.map { |row| row[:progress_percent].to_f }
        {
          total_targets: progress.size,
          green: percentages.count { |value| value >= 100 },
          yellow: percentages.count { |value| value >= 75 && value < 100 },
          red: percentages.count { |value| value < 75 }
        }
      end

      def monthly_target_summary(targets)
        targets.group_by { |target| target.month_name.presence || "Not Set" }.map do |month, rows|
          {
            month: month,
            target_records: rows.size,
            target_quantity: number(rows.sum { |target| target.target_quantity.to_f })
          }
        end
      end

      def approved_bill?(bill)
        status = bill.data["approval_status"].presence || bill.data["status"]
        status.to_s.downcase.include?("approved") && !status.to_s.downcase.include?("pending")
      end

      def current_dashboard_vrp
        user = current_api_user_payload
        return Vrp.find_by(id: user["id"]) if user["record_type"] == "Vrp"
        return Vrp.find_by(id: params[:vrp_id]) if user["user_type"].to_s.casecmp("admin").zero? && params[:vrp_id].present?
      end

      def default_month(months)
        current = Date.current.strftime("%B")
        months.find { |month| same_text?(month, current) } || months.last
      end

      def unique_count(targets, field)
        targets.filter_map { |target| target.public_send(field).to_s.downcase.strip.presence }.uniq.size
      end

      def progress_payload(target)
        assigned = target.target_quantity.to_f
        achieved = [target_achievement(target), assigned].min
        {
          target_mapping_id: target.id.to_s,
          month: target.month_name,
          fco: target.fco_name.presence || target.fco_id,
          ics: target.ics_name.presence || target.ics_id,
          village: target.village_name.presence || target.village_id,
          main_activity: target.main_activity_name,
          sub_activity: target.activity_name,
          completion_date: target.completion_date&.iso8601,
          assigned: number(assigned),
          achieved: number(achieved),
          pending: number([assigned - achieved, 0].max),
          progress_percent: assigned.positive? ? ((achieved / assigned) * 100).round(2) : 0
        }
      end

      # Keep the mobile dashboard totals identical to the existing VRP web dashboard.
      # The web calculation handles Main Activity Type, farmer/activity/month matching,
      # completion deadlines, approved Other targets, and the bill fallback.
      def web_parity_progress(targets, vrp)
        calculator = ModulesController.new
        bills = calculator.send(:vrp_dashboard_bills, vrp)
        rows = calculator.send(:vrp_dashboard_target_progress_rows, targets, bills)

        rows.map do |row|
          assigned = row[:target].to_f
          achieved = [row[:completed].to_f, assigned].min
          {
            target_mapping_id: row[:target_mapping_id],
            month: row[:month],
            fco: row[:fco],
            ics: row[:ics],
            village: row[:village],
            main_activity: row[:main_activity],
            sub_activity: row[:activity],
            completion_date: parse_dashboard_date(row[:completion_date]),
            assigned: number(assigned),
            achieved: number(achieved),
            pending: number([assigned - achieved, 0].max),
            progress_percent: assigned.positive? ? ((achieved / assigned) * 100).round(2) : 0
          }
        end
      end

      def parse_dashboard_date(value)
        return if value.blank? || value == "-"

        Date.strptime(value.to_s, "%d-%m-%Y").iso8601
      rescue ArgumentError
        value
      end

      def target_achievement(target)
        records = ModuleRecord.where(module_slug: %w[training-form seed-distribution-target papl360-target add-farmer-form])
          .select { |record| record.data["target_mapping_id"].to_s == target.id.to_s && active_record?(record) }
        training_ids = records.select { |record| record.module_slug == "training-form" }
          .flat_map { |record| Array(record.data["selected_farmer_ids"]).map(&:to_s) }.reject(&:blank?).uniq
        other = records.reject { |record| record.module_slug == "training-form" }.sum do |record|
          (record.data["achievement"].presence || record.data["no_farmer"].presence || Array(record.data["selected_farmer_ids"]).size).to_f
        end
        training_ids.size + other
      end

      def mapped_farmer_ids(target)
        ids = Array(target.afl_ids).map(&:to_s).reject(&:blank?).uniq
        return ids if ids.any?

        VrpIcsMapping.where(vrp_id: target.vrp_id).select do |mapping|
          location_match?(mapping.fco_id, mapping.fco_name, target.fco_id, target.fco_name) &&
            location_match?(mapping.ics_id, mapping.ics_name, target.ics_id, target.ics_name) &&
            location_match?(mapping.village_id, mapping.village_name, target.village_id, target.village_name)
        end.flat_map { |mapping| Array(mapping.afl_ids).map(&:to_s) }.reject(&:blank?).uniq
      end

      def location_match?(left_id, left_name, right_id, right_name)
        left = [left_id, left_name].compact_blank.map { |value| value.to_s.strip.downcase }
        right = [right_id, right_name].compact_blank.map { |value| value.to_s.strip.downcase }
        (left & right).any?
      end

      def active_record?(record)
        status = record.data["status"].to_s.strip.downcase
        !%w[inactive rejected returned deleted].include?(status) && !record.data["is_deleted"].to_s.casecmp("true").zero?
      end

      def same_text?(left, right)
        left.to_s.strip.casecmp(right.to_s.strip).zero?
      end

      def number(value)
        value.to_f == value.to_i ? value.to_i : value.to_f.round(2)
      end
    end
  end
end
