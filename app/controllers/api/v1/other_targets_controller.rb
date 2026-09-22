module Api
  module V1
    class OtherTargetsController < FarmerTargetBaseController
      MODULE_SLUG = "other-target".freeze
      RESOURCE_TITLE = "Other Target".freeze
      RESOURCE_KEY = "other_targets".freeze
      PARAM_KEY = :other_target

      def index
        render_list(RESOURCE_KEY)
      end

      def show
        render_show
      end

      def create
        render_create
      end

      def form_options
        render_form_options
      end

      def form_data
        options = farmer_target_api.form_options
        mappings = filter_form_mappings(Array(options[:target_mappings]))

        render json: {
          success: true,
          message: "Other Target form data fetched successfully.",
          filters: form_filter_payload,
          form_fields: options[:form_fields],
          current_vrp: options[:current_vrp],
          autofill: options[:autofill],
          upload_constraints: options[:upload_constraints],
          options: {
            months: Array(options[:months]),
            jeevika_jankars: named_options(mappings, :vrp_id, :jeevika_jankar_name),
            ics: option_values(mappings, :ics),
            villages: option_values(mappings, :village),
            main_activities: option_values(mappings, :main_activity),
            sub_activities: option_values(mappings, :sub_activity)
          },
          target_mappings: mappings,
          count: mappings.size
        }, status: :ok
      end

      def months
        values = Array(farmer_target_api.form_options[:months])

        render json: {
          success: true,
          message: "Other Target months fetched successfully.",
          months: values.map { |month| { id: month, name: month } },
          count: values.size
        }, status: :ok
      end

      def photos
        record = farmer_target_api.find(params[:id])
        unless record
          return render json: { success: false, message: "Other Target record not found." }, status: :not_found
        end

        photos = Array(record.data["field_photo"]).compact_blank.uniq.map.with_index do |path, index|
          {
            id: index + 1,
            url: path.to_s.match?(/\Ahttps?:\/\//i) ? path : "#{request.base_url}#{path}",
            filename: File.basename(path.to_s)
          }
        end

        render json: {
          success: true,
          other_target_id: record.id,
          photo_count: photos.size,
          photos: photos
        }, status: :ok
      end

      private

      def filter_form_mappings(mappings)
        mappings.select do |mapping|
          vrp_filter_matches?(mapping) &&
            filter_matches?(mapping[:month], params[:month]) &&
            filter_matches?(mapping[:ics], params[:ics].presence || params[:ics_name]) &&
            filter_matches?(mapping[:village], params[:village].presence || params[:village_name]) &&
            filter_matches?(mapping[:main_activity], params[:main_activity]) &&
            filter_matches?(mapping[:sub_activity], params[:sub_activity])
        end
      end

      def vrp_filter_matches?(mapping)
        selected_id = params[:jeevika_jankar_id].presence || params[:vrp_id]
        selected_name = params[:jeevika_jankar_name].presence || params[:vrp_name]
        filter_matches?(mapping[:vrp_id], selected_id) && filter_matches?(mapping[:jeevika_jankar_name], selected_name)
      end

      def filter_matches?(actual, selected)
        selected.blank? || actual.to_s.strip.casecmp(selected.to_s.strip).zero?
      end

      def option_values(mappings, key)
        mappings.filter_map { |mapping| mapping[key].presence }.uniq.sort
      end

      def named_options(mappings, id_key, name_key)
        mappings.filter_map do |mapping|
          id = mapping[id_key].presence
          name = mapping[name_key].presence
          next if id.blank? && name.blank?

          { id: id, name: name || id }
        end.uniq { |option| [option[:id].to_s, option[:name].to_s] }
      end

      def form_filter_payload
        {
          jeevika_jankar_id: params[:jeevika_jankar_id].presence || params[:vrp_id],
          jeevika_jankar_name: params[:jeevika_jankar_name].presence || params[:vrp_name],
          month: params[:month],
          ics: params[:ics].presence || params[:ics_name],
          village: params[:village].presence || params[:village_name],
          main_activity: params[:main_activity],
          sub_activity: params[:sub_activity]
        }
      end
    end
  end
end
