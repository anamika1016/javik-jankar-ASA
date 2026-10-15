module Api
  module V1
    class JjMappedFarmersController < BaseController
      def index
        result = jj_mapped_farmers_api.mapped_farmers(
          mobile_no: params[:mobile_no].presence || params[:vrp_mobile],
          month: params[:month], year: params[:year], village_id: params[:village_id]
        )

        render json: { success: true,
          message: "Jeevika Jankar mapped farmers fetched successfully." }.merge(result), status: :ok
      end

      # The dropdown on its own, so the app can fill it before any month is picked.
      def jeevika_jankars
        api = jj_mapped_farmers_api
        options = api.jeevika_jankar_options

        render json: {
          success: true,
          message: "Jeevika Jankar list fetched successfully.",
          login_type: api.login_type,
          can_choose_jeevika_jankar: api.login_type != "jeevika_jankar",
          selected_mobile_no: api.resolve_mobile_no(nil),
          jeevika_jankars: options,
          count: options.size
        }, status: :ok
      end

      def filters
        render json: { success: true,
          message: "Jeevika Jankar mapped farmer filters fetched successfully." }
          .merge(jj_mapped_farmers_api.filters), status: :ok
      end

      private

      def jj_mapped_farmers_api
        JjMappedFarmersApi.new(current_app_user: current_api_user_payload)
      end
    end
  end
end
