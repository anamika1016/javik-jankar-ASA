module Api
  module V1
    class FarmerTargetBaseController < BaseController
      private

      def current_app_user
        current_api_user_payload
      end

      def farmer_target_api(module_slug = self.class::MODULE_SLUG)
        FarmerTargetApi.new(
          current_app_user: current_app_user,
          module_slug: module_slug,
          exclude_record_id: params[:id]
        )
      end

      def render_list(resource_key)
        records = farmer_target_api.list
        render json: {
          success: true,
          message: "#{self.class::RESOURCE_TITLE} list fetched successfully.",
          resource_key => records,
          count: records.size
        }, status: :ok
      end

      def render_show
        record = farmer_target_api.find(params[:id])
        unless record
          return render json: { success: false, message: "#{self.class::RESOURCE_TITLE} record not found." }, status: :not_found
        end

        body = { success: true }
        body[self.class::RESOURCE_KEY.singularize] = farmer_target_api.record_payload(record)
        render json: body, status: :ok
      end

      def render_create
        merge_json_body_params!
        attrs = create_attrs
        result = farmer_target_api.create(attrs)

        unless result[:success]
          return render json: {
            success: false,
            message: "#{self.class::RESOURCE_TITLE} save failed.",
            errors: result[:errors]
          }, status: :unprocessable_entity
        end

        body = {
          success: true,
          message: "#{self.class::RESOURCE_TITLE} saved successfully."
        }
        body[self.class::RESOURCE_KEY.singularize] = farmer_target_api.record_payload(result[:record])
        render json: body, status: :created
      end

      def render_form_options
        render json: {
          success: true,
          options: farmer_target_api.form_options
        }, status: :ok
      end

      def create_attrs
        raw = params[self.class::PARAM_KEY].presence || params[:module_record].presence || params
        if raw.respond_to?(:to_unsafe_h)
          raw.to_unsafe_h.except("controller", "action", "format", "token", "authenticity_token", self.class::PARAM_KEY.to_s, "module_record")
        else
          Hash(raw)
        end
      end

      def merge_json_body_params!
        return if request.content_type.to_s.include?("multipart")
        return unless request.body.present?

        body = request.raw_post.to_s
        return if body.blank?

        json = JSON.parse(body)
        return unless json.is_a?(Hash)

        json.each { |key, value| params[key] = value if params[key].blank? }
      rescue JSON::ParserError
        nil
      end
    end
  end
end
