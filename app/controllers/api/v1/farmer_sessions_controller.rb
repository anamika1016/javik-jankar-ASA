module Api
  module V1
    # Android farmer login. The farmer types a mobile number or an Aadhaar
    # number; either way the OTP goes only to the mobile number the ASA
    # register holds for that farmer, never to a number typed into the app.
    #
    # Deliberately not under BaseController: that one authenticates staff and
    # Jeevika Jankar tokens, and a farmer session must stay separate from both.
    class FarmerSessionsController < ActionController::API
      def send_otp
        merge_json_body_params!

        mobile_no = param_value(:mobile_no, :mobile, :phone)
        aadhaar_no = param_value(:aadhaar_no, :aadhaar, :aadhar_no)
        if mobile_no.blank? && aadhaar_no.blank?
          return render_error("Mobile number or Aadhaar number is required.")
        end

        identifier_type = mobile_no.present? ? "mobile" : "aadhaar"
        lookup = if mobile_no.present?
          FarmerRegisterLookup.by_mobile(mobile_no)
        else
          FarmerRegisterLookup.by_aadhaar(aadhaar_no)
        end
        return render_error(lookup.error, status: :not_found) unless lookup.found?

        farmer = lookup.farmer
        registered_mobile = farmer["mobile_no"].to_s.gsub(/\D/, "")
        if registered_mobile.length < 10
          return render_error("This farmer has no registered mobile number. Please contact your FCO.")
        end

        if FarmerLoginOtp.resend_blocked?(registered_mobile)
          return render_error("An OTP was just sent. Please wait a minute before trying again.",
            status: :too_many_requests)
        end

        issued = FarmerLoginOtp.issue(
          farmer: farmer,
          mobile: registered_mobile,
          identifier_type: identifier_type,
          aadhaar_no: aadhaar_no
        )

        sms = OtpSmsSender.new(registered_mobile, issued[:otp], purpose: :login).deliver
        return render_error(sms_error_message(sms)) unless sms.success?

        FarmerLoginOtp.note_sent(registered_mobile)

        render json: {
          success: true,
          message: "OTP sent to the registered mobile number.",
          otp_token: issued[:otp_token],
          mobile_masked: FarmerLoginOtp.mask_mobile(registered_mobile),
          expires_in_seconds: FarmerLoginOtp::TTL.to_i
        }, status: :ok
      end

      def verify_otp
        merge_json_body_params!

        otp = param_value(:otp, :otp_code)
        otp_token = param_value(:otp_token)
        return render_error("OTP and otp_token are required.") if otp.blank? || otp_token.blank?

        data = FarmerLoginOtp.verify(otp_token: otp_token, otp: otp)
        unless data.is_a?(Hash)
          return render_error(verify_failure_message(data), status: :unauthorized)
        end

        # Normally the register's answer from the send step is still held, so
        # verifying costs no outbound call at all. It is only re-read if that
        # has expired -- the OTP itself is what was verified, not this payload.
        farmer = FarmerLoginOtp.issued_farmer(data)
        if farmer.blank?
          lookup = FarmerRegisterLookup.by_mobile(data["mobile"])
          unless lookup.found?
            return render_error("Farmer record could not be read. Please try again.", status: :not_found)
          end

          farmer = lookup.farmer
        end

        login = FarmerAppLogin.record_login!(
          farmer: farmer,
          identifier_type: data["identifier_type"],
          aadhaar_no: param_value(:aadhaar_no),
          ip: request.remote_ip,
          device: request.headers["X-Device-Name"].presence || request.user_agent,
          app_version: request.headers["X-App-Version"]
        )

        render json: {
          success: true,
          message: "Logged in successfully.",
          token: FarmerApiToken.encode(login),
          farmer: farmer_payload(farmer, login)
        }, status: :ok
      end

      # The app's own profile screen. Always served live from the register.
      def profile
        login = FarmerApiToken.find_login(bearer_token)
        return render_error("Unauthorized. Please login again.", status: :unauthorized) unless login

        lookup = FarmerRegisterLookup.by_mobile(login.mobile_no)
        return render_error(lookup.error, status: :not_found) unless lookup.found?

        render json: {
          success: true,
          farmer: farmer_payload(lookup.farmer, login),
          detail: lookup.farmer
        }, status: :ok
      end

      def logout
        render json: { success: true, message: "Logged out." }, status: :ok
      end

      private

      def farmer_payload(farmer, login)
        {
          id: farmer["id"],
          full_name: farmer["full_name"],
          father_husband_name: farmer["father_husband_name"],
          mobile_masked: login.masked_mobile,
          aadhaar_masked: login.masked_aadhaar,
          gender: farmer["gender"],
          age: farmer["age"],
          occupation: farmer["occupation"],
          village_name: login.village_name,
          district_name: login.district_name,
          state_name: login.state_name,
          ics_team_name: farmer["ics_team_name"],
          tracenet_id: farmer["tracenet_id"],
          is_lead_farmer: farmer["is_lead_farmer"],
          login_count: login.login_count,
          last_logged_in_at: login.last_logged_in_at
        }
      end

      def verify_failure_message(reason)
        case reason
        when :expired then "OTP has expired. Please request a new one."
        when :too_many_attempts then "Too many wrong attempts. Please request a new OTP."
        when :consumed then "This OTP has already been used. Please request a new one."
        else "Invalid or expired OTP."
        end
      end

      def sms_error_message(sms_result)
        reason = sms_result.message.to_s.strip
        reason = "#{reason}." if reason.present? && !reason.match?(/[.!?]\z/)

        ["OTP could not be sent.", reason.presence, "Please try again."].compact.join(" ")
      end

      def param_value(*keys)
        keys.each do |key|
          value = params[key].to_s.strip
          return value if value.present?
        end
        nil
      end

      def render_error(message, status: :unprocessable_entity)
        render json: { success: false, message: message }, status: status
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")

        params[:token].presence
      end

      def merge_json_body_params!
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
