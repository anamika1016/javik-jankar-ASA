module Api
  module V1
    class TargetMappingsController < BaseController
      DEFAULT_LIMIT = 100
      MAX_LIMIT = 200

      # Picking several sub activities saves one row per sub activity, so the raw
      # table holds many more rows than the mappings a user actually made.  The
      # web list collapses a submission back into one row and the app has to show
      # the same thing, so the rows are grouped here the same way.
      TARGET_BATCH_WINDOW = 10.seconds
      # Rows are read newest first, so a submission's rows are next to each other
      # and only the oldest batch read can be cut in half.  Enough rows are read
      # to fill the asked-for mappings several times over, and the batch sitting
      # on the cut is dropped rather than returned with sub activities missing.
      BATCH_ROW_HEADROOM = 25
      MAX_BATCH_ROWS = 2_000

      def recent
        batches = filtered_mapping_batches
        farmer_ids = batches.flatten.flat_map { |mapping| normalized_afl_ids(mapping.afl_ids) }.uniq
        farmers_by_id = Afl.where(id: farmer_ids).index_by { |farmer| farmer.id.to_s }

        render json: {
          success: true,
          message: "Recent target mappings fetched successfully.",
          target_mappings: batches.map { |batch| mapping_payload(batch, farmers_by_id) },
          count: batches.size
        }, status: :ok
      end

      private

      def filtered_mapping_batches
        rows = filtered_mappings
        batches = rows.group_by { |mapping| batch_signature(mapping) }
          .flat_map { |_signature, grouped| submission_batches(grouped) }
          .sort_by { |batch| -batch.map { |mapping| batch_time(mapping) }.max.to_f }
        batches = batches[0...-1] if rows.size >= batch_row_limit && batches.size > 1
        batches.first(requested_limit)
      end

      def filtered_mappings
        scope = visible_mappings.includes(:vrp, :vrp_ics_mapping)
        scope = scope.where("LOWER(month_name) = ?", params[:month].to_s.strip.downcase) if params[:month].present?
        scope = apply_search(scope) if params[:search].present?
        scope.order("target_mappings.updated_at DESC").limit(batch_row_limit).to_a
      end

      def batch_row_limit
        [requested_limit * BATCH_ROW_HEADROOM, MAX_BATCH_ROWS].min
      end

      # Saving a mapping writes every sub activity row in the same moment, and
      # editing it re-writes them all, so updated_at is what ties a batch
      # together — created_at drifts apart once a sub activity is added later.
      def batch_time(mapping)
        mapping.updated_at || mapping.created_at || Time.zone.at(0)
      end

      def batch_signature(mapping)
        [
          mapping.vrp_id, mapping.fco_id, mapping.ics_id, mapping.village_id,
          mapping.month_name, mapping.completion_date,
          mapping.main_activity_name.to_s.strip.downcase
        ]
      end

      # Sub activities mapped at some other time stay a separate mapping.
      def submission_batches(rows)
        rows.sort_by { |mapping| batch_time(mapping) }.slice_when do |previous, current|
          batch_time(current) - batch_time(previous) > TARGET_BATCH_WINDOW
        end.to_a
      end

      def normalized_afl_ids(ids)
        parsed = ids.is_a?(String) ? JSON.parse(ids) : ids
        Array(parsed).map(&:to_s).compact_blank.uniq
      rescue JSON::ParserError
        []
      end

      def activity_values(value)
        case value
        when Array
          value.flat_map { |item| activity_values(item) }
        when String
          stripped = value.strip
          return [] if stripped.blank?
          return activity_values(JSON.parse(stripped)) if stripped.start_with?("[")

          [stripped]
        else
          Array(value).flat_map { |item| activity_values(item) }
        end.map { |item| item.to_s.strip }.reject { |item| item.blank? || item == "__common__" }.uniq
      rescue JSON::ParserError
        [value.to_s.strip].reject { |item| item.blank? || item == "__common__" }
      end

      def visible_mappings
        payload = current_api_user_payload
        return TargetMapping.all if payload["user_type"].to_s.casecmp("admin").zero?
        return TargetMapping.where(vrp_id: payload["id"]) if payload["record_type"] == "Vrp"

        TargetMapping.where(created_by_type: payload["record_type"], created_by_id: payload["id"])
      end

      def apply_search(scope)
        term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
        scope.left_joins(:vrp).where(
          "vrps.name ILIKE :term OR target_mappings.fco_name ILIKE :term OR " \
          "target_mappings.ics_name ILIKE :term OR target_mappings.village_name ILIKE :term OR " \
          "target_mappings.month_name ILIKE :term OR target_mappings.main_activity_name ILIKE :term OR " \
          "target_mappings.activity_name ILIKE :term",
          term: term
        )
      end

      def requested_limit
        limit = params[:limit].to_i
        limit = DEFAULT_LIMIT if limit <= 0
        [limit, MAX_LIMIT].min
      end

      def mapping_payload(batch, farmers_by_id)
        # The whole batch was saved together, so the targets are the same on
        # every row; only the sub activity and the farmers differ.
        mapping = batch.first
        farmer_ids = batch.flat_map { |row| normalized_afl_ids(row.afl_ids) }.uniq
        sub_activities = batch.flat_map { |row| activity_values(row.activity_name) }.uniq
        weekly_targets = mapping.weekly_target_values

        {
          id: mapping.id,
          target_mapping_ids: batch.map(&:id),
          jeevika_jankar_id: mapping.vrp_id,
          jeevika_jankar_name: mapping.vrp&.name,
          fco_id: mapping.fco_id,
          fco_name: mapping.fco_name,
          ics_id: mapping.ics_id,
          ics_name: mapping.ics_name,
          village_id: mapping.village_id,
          village_name: mapping.village_name,
          month: mapping.month_name,
          completion_date: mapping.completion_date&.iso8601,
          main_activity: mapping.main_activity_name,
          sub_activity: sub_activities.join(", "),
          sub_activities: sub_activities,
          main_activity_type: target_main_activity_type(mapping),
          training_targets: {
            opg_training: mapping.opg_training_target,
            general_training_meeting: mapping.week_wise_opg_target,
            input_demo_inm: mapping.input_demo_inm_target,
            input_demo_pm: mapping.input_demo_pm_target,
            ffs: mapping.ffs_target
          },
          farmer_target: mapping.target_quantity,
          weekly_targets: {
            week_1: weekly_targets[0],
            week_2: weekly_targets[1],
            week_3: weekly_targets[2],
            week_4: weekly_targets[3]
          },
          farmer_count: farmer_ids.size,
          farmers: farmer_ids.map { |id| farmer_payload(id, farmers_by_id[id]) },
          created_at: batch.filter_map(&:created_at).min&.iso8601,
          updated_at: batch.filter_map(&:updated_at).max&.iso8601
        }
      end

      def farmer_payload(id, farmer)
        {
          id: id,
          farmer_name: farmer&.farmer_name,
          father_name: farmer&.father_name,
          tracenet_no: farmer&.tracenet_no,
          mobile_no: farmer&.mobile_no,
          village_name: farmer&.village_name
        }
      end

      def target_main_activity_type(mapping)
        settings = target_activity_type_settings
        main_key = mapping.main_activity_name.to_s.strip.downcase
        sub_key = mapping.activity_name.to_s.strip.downcase
        settings[:main][main_key].presence || settings[:main][sub_key].presence || settings[:sub][sub_key].presence || "Training"
      end

      def target_activity_type_settings
        return @target_activity_type_settings if defined?(@target_activity_type_settings)

        main = ModuleRecord.where(module_slug: "add-activity-group").order(created_at: :desc).each_with_object({}) do |record, values|
          next if record.data["status"].to_s.casecmp("Inactive").zero?

          name = (record.data["main_activity_name"].presence || record.data["activity_group_name"]).to_s.strip.downcase
          values[name] ||= record.data["main_activity_type"].presence || "Training" if name.present?
        end
        sub = ModuleRecord.where(module_slug: "add-vrp-activity").order(created_at: :desc).each_with_object({}) do |record, values|
          next if record.data["status"].to_s.casecmp("Inactive").zero?

          main_name = (record.data["main_activity"].presence || record.data["activity_group"]).to_s.strip.downcase
          sub_name = (record.data["sub_activity_name"].presence || record.data["activity_name"]).to_s.strip.downcase
          values[sub_name] ||= main[main_name] if sub_name.present? && main[main_name].present?
        end
        @target_activity_type_settings = { main: main, sub: sub }
      end
    end
  end
end
