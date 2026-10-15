module Api
  module V1
    class BaseController < ActionController::API
      include AppUserPayload

      before_action :authenticate_api_user!

      private

      def authenticate_api_user!
        user = current_api_user
        return if user

        render json: { success: false, message: "Unauthorized. Please login again." }, status: :unauthorized
      end

      def current_api_user
        return @current_api_user if defined?(@current_api_user)

        @current_api_user = ApiAuthToken.find_user(bearer_token)
      end

      # Built once per request. The access rules read the signed-in user over and
      # over - a list asks for it per row - and building the payload runs its own
      # queries for the Jeevika Jankar types, so rebuilding it each time put
      # hundreds of queries behind a single response.
      def current_api_user_payload
        return @current_api_user_payload if defined?(@current_api_user_payload)
        return @current_api_user_payload = nil unless current_api_user

        @current_api_user_payload = app_user_session_payload(current_api_user)
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")

        params[:token].presence
      end

      def vrp_agreement_required?(user)
        user.is_a?(Vrp) &&
          Vrp.column_names.include?("agreement_accepted_at") &&
          !user.agreement_accepted?
      end
    end
  end
end
