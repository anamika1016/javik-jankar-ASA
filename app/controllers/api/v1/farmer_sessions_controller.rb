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
        start_login(resend: false)
      end

      # Same path as send, but keyed off the token the app already holds so a
      # farmer does not have to retype an Aadhaar to get a second code.
      def resend_otp
        merge_json_body_params!
        start_login(resend: true)
      end

      def verify_otp
        merge_json_body_params!

        otp = param_value(:otp, :otp_code)
        otp_token = param_value(:otp_token)
        return render_error("OTP and otp_token are required.") if otp.blank? || otp_token.blank?

        mobile = FarmerLoginOtp.mobile_for(otp_token)
        if (lock = FarmerLoginLock.active_lock(mobile))
          return render_error(lock_message(lock), status: :locked)
        end

        otp_request = FarmerLoginOtp.verify(otp_token: otp_token, otp: otp)
        return handle_failed_verify(otp_request, mobile) unless otp_request.is_a?(FarmerLoginOtpRequest)

        # Normally the register's answer from the send step is still held, so
        # verifying costs no outbound call at all. It is only re-read if that
        # has expired -- the OTP itself is what was verified, not this payload.
        farmer = FarmerLoginOtp.issued_farmer(otp_request)
        if farmer.blank?
          lookup = FarmerRegisterLookup.by_mobile(otp_request.mobile_no)
          unless lookup.found?
            return render_error("Farmer record could not be read. Please try again.", status: :not_found)
          end

          farmer = lookup.farmer
        end

        # Holding the phone is proof enough; past wrong guesses are forgiven.
        FarmerLoginLock.clear!(otp_request.mobile_no)

        login = FarmerAppLogin.record_login!(
          farmer: farmer,
          identifier_type: otp_request.identifier_type,
          aadhaar_no: param_value(:aadhaar_no),
          ip: request.remote_ip,
          device: param_value(:device_name, :device) ||
            request.headers["X-Device-Name"].presence || request.user_agent,
          app_version: param_value(:app_version) || request.headers["X-App-Version"],
          latitude: location_coordinate(:latitude),
          longitude: location_coordinate(:longitude),
          place: location_place
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

      # Shared by send and resend: find the farmer, check the number is usable
      # and not locked out, then text a fresh code.
      def start_login(resend:)
        mobile_no = param_value(:mobile_no, :mobile, :phone)
        aadhaar_no = param_value(:aadhaar_no, :aadhaar, :aadhar_no)
        mobile_no ||= FarmerLoginOtp.mobile_for(param_value(:otp_token)) if resend

        if mobile_no.blank? && aadhaar_no.blank?
          return render_error("Mobile number or Aadhaar number is required.")
        end
        if mobile_no.present? && !FarmerAppLogin.valid_mobile?(mobile_no)
          return render_error(FarmerAppLogin::INVALID_MOBILE_MESSAGE)
        end

        identifier_type = mobile_no.present? ? "mobile" : "aadhaar"
        lookup = mobile_no.present? ? FarmerRegisterLookup.by_mobile(mobile_no) : FarmerRegisterLookup.by_aadhaar(aadhaar_no)
        return render_error(lookup.error, status: :not_found) unless lookup.found?

        farmer = lookup.farmer
        # Held to the same rule as typed input: the register has rows with
        # blank or placeholder numbers, and an OTP sent to one of those is
        # either undeliverable or lands on a stranger's phone.
        unless FarmerAppLogin.valid_mobile?(farmer["mobile_no"])
          return render_error("This farmer has no valid registered mobile number. Please contact your FCO.")
        end

        registered_mobile = FarmerAppLogin.normalize_mobile(farmer["mobile_no"])
        if (lock = FarmerLoginLock.active_lock(registered_mobile))
          return render_error(lock_message(lock), status: :locked)
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

        render json: {
          success: true,
          message: resend ? "A new OTP has been sent to the registered mobile number."
                          : "OTP sent to the registered mobile number.",
          otp_token: issued[:otp_token],
          mobile_masked: FarmerLoginOtp.mask_mobile(registered_mobile),
          expires_in_seconds: FarmerLoginOtp::TTL.to_i,
          resend_available_in_seconds: FarmerLoginOtp::RESEND_INTERVAL.to_i
        }, status: :ok
      end

      # A wrong OTP is charged to the mobile, not to the one code, so fresh
      # OTPs cannot be used to buy three more guesses each time.
      def handle_failed_verify(reason, mobile)
        if reason == :wrong_otp && mobile.present?
          lock = FarmerLoginLock.register_failure!(mobile)
          return render_error(lock_message(lock), status: :locked) if lock&.locked?

          left = lock&.attempts_left.to_i
          suffix = left.positive? ? " #{left} attempt#{'s' if left != 1} left." : ""
          return render_error("Invalid OTP.#{suffix}", status: :unauthorized)
        end

        render_error(verify_failure_message(reason), status: :unauthorized)
      end

      def lock_message(lock)
        "Too many wrong OTP attempts. This mobile number is locked for " \
          "#{lock.minutes_remaining} more minute#{'s' if lock.minutes_remaining != 1}."
      end

      # Coordinates are read from the JSON body as well as from headers.
      # Putting them in the body is the natural thing for the app to do, and
      # when it did, a header-only reader recorded nothing and the web list
      # showed every login with no location at all.
      def location_coordinate(kind)
        raw =
          if kind == :latitude
            param_value(:latitude, :lat) || request.headers["X-Latitude"]
          else
            param_value(:longitude, :lng, :long) || request.headers["X-Longitude"]
          end

        value = Float(raw.to_s.strip, exception: false)
        return if value.nil?
        # 0,0 is in the Atlantic: it is what a device reports when it has no
        # fix, not a place a farmer logged in from.
        return if value.zero?

        kind == :latitude ? value.clamp(-90, 90) : value.clamp(-180, 180)
      end

      def location_place
        param_value(:location, :place, :address) || request.headers["X-Location"].presence
      end

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
