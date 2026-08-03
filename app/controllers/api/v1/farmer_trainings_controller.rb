module Api
  module V1
    class FarmerTrainingsController < FarmerTargetBaseController
      MODULE_SLUG = "training-form".freeze
      RESOURCE_TITLE = "Farmer Training Form".freeze
      RESOURCE_KEY = "farmer_trainings".freeze
      PARAM_KEY = :farmer_training

      def index
        render_list(RESOURCE_KEY)
      end

      def show
        render_show
      end

      def photos
        record = farmer_target_api.find(params[:id])
        unless record
          return render json: { success: false, message: "Farmer Training Form record not found." }, status: :not_found
        end

        paths = Array(record.data["training_photo_upload_with_geo_tag"]).compact_blank
        photos = paths.map.with_index do |path, index|
          {
            id: index + 1,
            url: path.to_s.match?(/\Ahttps?:\/\//i) ? path : "#{request.base_url}#{path}",
            filename: File.basename(path.to_s)
          }
        end

        render json: {
          success: true,
          farmer_training_id: record.id,
          photo_count: photos.size,
          photos: photos
        }, status: :ok
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
        farmers, available_farmers, completed_farmer_ids = farmer_lists_for(mappings)

        render json: {
          success: true,
          message: "Farmer Training form data fetched successfully.",
          filters: form_filter_payload,
          autofill: options[:autofill],
          options: {
            months: option_values(mappings, :month),
            fcos: named_options(mappings, :fco_id, :fco_name),
            fpos: named_options(mappings, :fpo_id, :fpo_name),
            ics: option_values(mappings, :ics),
            villages: option_values(mappings, :village),
            main_activities: option_values(mappings, :main_activity),
            sub_activities: option_values(mappings, :sub_activity),
            training_methods: options[:training_methods]
          },
          target_mappings: mappings,
          farmers: farmers,
          available_farmers: available_farmers,
          farmer_count: farmers.size,
          available_farmer_count: available_farmers.size
        }, status: :ok
      end

      def farmers
        mappings = filter_form_mappings(Array(farmer_target_api.form_options[:target_mappings]))
        all_farmers, available_farmers, completed_farmer_ids = farmer_lists_for(mappings)

        render json: {
          success: true,
          message: "Farmer Training farmer list fetched successfully.",
          filters: form_filter_payload,
          target_mapping_ids: mappings.map { |mapping| mapping[:target_mapping_id] }.compact.uniq,
          farmers: available_farmers,
          count: available_farmers.size,
          all_farmer_count: all_farmers.size,
          completed_farmer_ids: completed_farmer_ids
        }, status: :ok
      end

      def months
        mappings = Array(farmer_target_api.form_options[:target_mappings])
        values = option_values(mappings, :month)

        render json: {
          success: true,
          message: "Farmer Training months fetched successfully.",
          months: values.map { |month| { id: month, name: month } },
          count: values.size
        }, status: :ok
      end

      def mapped_farmers
        mappings = filter_form_mappings(Array(farmer_target_api.form_options[:target_mappings]))
        farmers, _available_farmers, completed_farmer_ids = farmer_lists_for(mappings)
        rows = farmers.map do |farmer|
          completed = completed_farmer_ids.include?(farmer[:id].to_s)
          farmer.merge(is_completed: completed, is_available: !completed)
        end

        render json: {
          success: true,
          message: "Mapped Farmer list fetched successfully.",
          filters: form_filter_payload,
          target_mapping_ids: mappings.map { |mapping| mapping[:target_mapping_id] }.compact.uniq,
          mapped_farmers: rows,
          count: rows.size,
          available_count: rows.count { |farmer| farmer[:is_available] },
          completed_count: rows.count { |farmer| farmer[:is_completed] }
        }, status: :ok
      end

      private

      def filter_form_mappings(mappings)
        mappings.select do |mapping|
          filter_matches?(mapping[:month], params[:month]) &&
            filter_matches?(mapping[:main_activity_type], params[:main_activity_type]) &&
            fco_filter_matches?(mapping) &&
            filter_matches?(mapping[:ics], params[:ics].presence || params[:ics_name]) &&
            filter_matches?(mapping[:village], params[:village].presence || params[:village_name]) &&
            filter_matches?(mapping[:main_activity], params[:main_activity]) &&
            filter_matches?(mapping[:sub_activity], params[:sub_activity])
        end
      end

      def farmer_lists_for(mappings)
        completed_farmer_ids = mappings.flat_map { |mapping| Array(mapping[:completed_farmer_ids]) }.map(&:to_s).uniq
        farmers = mappings
          .flat_map { |mapping| Array(mapping[:farmers]) }
          .uniq { |farmer| farmer[:id].to_s }
        available_farmers = farmers.reject { |farmer| completed_farmer_ids.include?(farmer[:id].to_s) }
        [farmers, available_farmers, completed_farmer_ids]
      end

      def fco_filter_matches?(mapping)
        selected_id = params[:fco_id].presence || params[:fpo_id]
        selected_name = params[:fco_name].presence || params[:fpo_name].presence || params[:fco].presence || params[:fpo]
        filter_matches?(mapping[:fco_id], selected_id) && filter_matches?(mapping[:fco_name], selected_name)
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
          month: params[:month],
          main_activity_type: params[:main_activity_type],
          fco_id: params[:fco_id].presence || params[:fpo_id],
          fco_name: params[:fco_name].presence || params[:fpo_name].presence || params[:fco].presence || params[:fpo],
          ics: params[:ics].presence || params[:ics_name],
          village: params[:village].presence || params[:village_name],
          main_activity: params[:main_activity],
          sub_activity: params[:sub_activity]
        }
      end
    end
  end
end
