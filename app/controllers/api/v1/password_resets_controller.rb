module Api
  module V1
    class PasswordResetsController < BaseController
      skip_before_action :authenticate_api_user!

      def send_otp
        merge_json_body_params!

        username = params[:username].presence || params[:login].presence || params[:user_name].presence
        if username.blank?
          return render json: { success: false, message: "Username is required." }, status: :unprocessable_entity
        end

        account = ApiPasswordReset.find_account(username)
        unless account
          return render json: {
            success: false,
            message: "Username not matched. OTP not sent."
          }, status: :unprocessable_entity
        end

        mobile = ApiPasswordReset.account_mobile(account)
        if mobile.blank?
          return render json: {
            success: false,
            message: "Registered mobile number not found. OTP not sent."
          }, status: :unprocessable_entity
        end

        issued = ApiPasswordReset.issue(account: account, username: username)
        sms_result = OtpSmsSender.new(mobile, issued[:otp], purpose: :forgot_password).deliver

        unless sms_result.success?
          return render json: {
            success: false,
            message: otp_sms_error_message(sms_result)
          }, status: :unprocessable_entity
        end

        render json: {
          success: true,
          message: "OTP sent to registered mobile number.",
          reset_token: issued[:reset_token],
          username: username.to_s.strip,
          mobile_masked: ApiPasswordReset.mask_mobile(mobile),
          expires_in_seconds: ApiPasswordReset::TTL.to_i
        }, status: :ok
      end

      def reset
        merge_json_body_params!

        username = params[:username].presence || params[:login].presence || params[:user_name].presence
        otp = params[:otp].presence || params[:otp_code].presence
        reset_token = params[:reset_token]
        password = params[:password].to_s
        confirmed_password = params[:confirmed_password].to_s.presence || params[:password_confirmation].to_s

        if username.blank? || otp.blank? || reset_token.blank?
          return render json: {
            success: false,
            message: "Username, OTP, and reset_token are required."
          }, status: :unprocessable_entity
        end

        if password.blank? || password != confirmed_password
          return render json: {
            success: false,
            message: "Password and Confirm Password must match."
          }, status: :unprocessable_entity
        end

        account = ApiPasswordReset.verify(reset_token: reset_token, otp: otp, username: username)
        unless account
          return render json: {
            success: false,
            message: "Invalid or expired OTP."
          }, status: :unauthorized
        end

        ApiPasswordReset.update_password!(account, password)

        render json: {
          success: true,
          message: "Password reset successfully. Please sign in."
        }, status: :ok
      end

      private

      def merge_json_body_params!
        return if params[:username].present? || params[:otp].present? || params[:reset_token].present?
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
