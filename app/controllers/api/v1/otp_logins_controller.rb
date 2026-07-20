module Api
  module V1
    class OtpLoginsController < BaseController
      skip_before_action :authenticate_api_user!

      def send_otp
        merge_json_body_params!

        mobile = params[:mobile_no].presence || params[:mobile].presence || params[:phone].presence
        if mobile.blank?
          return render json: { success: false, message: "Mobile number is required." }, status: :unprocessable_entity
        end

        vrp = ApiLoginOtp.find_vrp_by_mobile(mobile)
        unless vrp
          return render json: {
            success: false,
            message: "Registered mobile number not found."
          }, status: :unprocessable_entity
        end

        if vrp_agreement_required?(vrp)
          return render json: {
            success: false,
            error: "agreement_required",
            message: "Please accept the VRP agreement on the web portal before using the app."
          }, status: :forbidden
        end

        issued = ApiLoginOtp.issue(user: vrp, mobile: mobile)
        sms_result = OtpSmsSender.new(mobile, issued[:otp], purpose: :login).deliver

        unless sms_result.success?
          return render json: {
            success: false,
            message: otp_sms_error_message(sms_result)
          }, status: :unprocessable_entity
        end

        render json: {
          success: true,
          message: "OTP sent to registered mobile number.",
          otp_token: issued[:otp_token],
          mobile_masked: ApiLoginOtp.mask_mobile(mobile),
          expires_in_seconds: ApiLoginOtp::TTL.to_i
        }, status: :ok
      end

      def verify_otp
        merge_json_body_params!

        mobile = params[:mobile_no].presence || params[:mobile].presence || params[:phone].presence
        otp = params[:otp].presence || params[:otp_code].presence
        otp_token = params[:otp_token]

        if mobile.blank? || otp.blank? || otp_token.blank?
          return render json: {
            success: false,
            message: "Mobile number, OTP, and otp_token are required."
          }, status: :unprocessable_entity
        end

        user = ApiLoginOtp.verify(otp_token: otp_token, otp: otp, mobile: mobile)
        unless user
          return render json: {
            success: false,
            message: "Invalid or expired OTP."
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

      private

      def merge_json_body_params!
        return if params[:mobile_no].present? || params[:otp].present? || params[:otp_token].present?
        return unless request.body.present?

        body = request.raw_post.to_s
        return if body.blank?

        json = JSON.parse(body)
        return unless json.is_a?(Hash)

        json.each { |key, value| params[key] = value if params[key].blank? }
      rescue JSON::ParserError
        nil
      end

      def otp_sms_error_message(sms_result)
        reason = sms_result.message.to_s.strip
        reason = "#{reason}." if reason.present? && !reason.match?(/[.!?]\z/)

        ["OTP could not be sent.", reason.presence, "Please try again."].compact.join(" ")
      end
    end
  end
end
