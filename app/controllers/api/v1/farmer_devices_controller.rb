module Api
  module V1
    # Where the Android app hands over its FCM token so news and videos
    # published for the farmer's state can be pushed to the phone.
    class FarmerDevicesController < ActionController::API
      def create
        return unless (login = authenticate_farmer!)

        token = param_value(:fcm_token, :token, :device_token, :registration_token)
        if token.blank?
          return render_error("missing_fcm_token",
            "Send the device's FCM registration token as \"fcm_token\".")
        end

        device = FarmerDevice.register!(
          login: login, token: token,
          platform: param_value(:platform) || "android",
          app_version: param_value(:app_version) || request.headers["X-App-Version"]
        )

        render json: {
          success: true,
          message: "This device will now receive notifications for #{login.state_name.presence || 'all states'}.",
          device_id: device.id,
          state: login.state_name,
          state_id: login.state_id
        }, status: :ok
      end

      # Called on sign-out. Without it a shared handset keeps receiving the
      # previous farmer's state's notifications.
      def destroy
        return unless (login = authenticate_farmer!)

        token = param_value(:fcm_token, :token, :device_token, :registration_token)
        scope = FarmerDevice.where(farmer_app_login_id: login.id)
        scope = scope.where(token: token) if token.present?
        removed = scope.delete_all

        render json: { success: true, message: "Notifications stopped.", removed: removed }, status: :ok
      end

      private

      def authenticate_farmer!
        token = bearer_token
        if token.blank?
          return render_error("missing_token",
            "Authorization header is missing. Send 'Authorization: Bearer <token>' using " \
            "the token returned by /api/v1/farmer/login/otp/verify.", status: :unauthorized)
        end

        login = FarmerApiToken.find_login(token)
        return login if login

        render_error("invalid_token", "Session expired. Please login again.", status: :unauthorized)
      end

      def render_error(error, message, status: :unprocessable_entity)
        render json: { success: false, error: error, message: message }, status: status
        nil
      end

      def param_value(*keys)
        merge_json_body_params!
        keys.each do |key|
          value = params[key].to_s.strip
          return value if value.present?
        end
        nil
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")

        params[:token].presence
      end

      def merge_json_body_params!
        return if @json_body_merged

        @json_body_merged = true
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
