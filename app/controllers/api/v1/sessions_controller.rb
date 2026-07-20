module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_api_user!, only: [ :create ]

      def create
        merge_json_body_params!

        login = params[:login].presence || params[:email].presence || params[:username].presence
        password = params[:password]

        user = AppUserAuthenticator.authenticate(login: login, password: password)

        unless user
          return render json: {
            success: false,
            message: "Invalid username or password."
          }, status: :unauthorized
        end

        if vrp_agreement_required?(user)
          return render json: {
            success: false,
            error: "agreement_required",
            message: "Please accept the VRP agreement on the web portal before using the app."
          }, status: :forbidden
        end

        token = ApiAuthToken.encode(user)

        render json: {
          success: true,
          message: "Logged in successfully.",
          token: token,
          user: app_user_session_payload(user)
        }, status: :ok
      end

      def show
        render json: {
          success: true,
          user: current_api_user_payload
        }, status: :ok
      end

      def destroy
        render json: {
          success: true,
          message: "Logged out successfully."
        }, status: :ok
      end

      private

      # Postman sometimes sends raw JSON with Content-Type: text/plain.
      def merge_json_body_params!
        return if params[:login].present? || params[:password].present?
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
