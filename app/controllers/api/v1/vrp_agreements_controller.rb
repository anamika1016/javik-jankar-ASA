require "rexml/document"

module Api
  module V1
    class VrpAgreementsController < BaseController
      skip_before_action :authenticate_api_user!, only: %i[show accept]

      AGREEMENT_TEXT = {
        intro: "I hereby confirm that I am voluntarily associated with Action For Social Advancement as a “Jeevika Jankar” for supporting farmer outreach and programme implementation activities in my village/ area. I understand and acknowledge that:",
        terms: [
          "My engagement is project-based and activity-based.",
          "I am not an employee, worker, or staff member of ASA.",
          "No employer-employee relationship is created through this engagement.",
          "I shall receive a facilitation fee/ honorarium based on approved activities carried out by me.",
          "I shall not be entitled to salary, leave, PF, ESI, gratuity, bonus, or any other employee benefits.",
          "ASA may discontinue my engagement at any time based on programme requirements or performance considerations.",
          "I am free to pursue my own occupation, farming, business, or other activities."
        ],
        acceptance: "I have read and understood the above conditions and agree to participate as a Jeevika Jankar."
      }.freeze

      # GET /api/v1/jeevika-jankar-agreement
      # Available to a JJ with either a bearer token or username/password. This
      # is the pre-login path for JJs whose first login is blocked pending signature.
      def show
        merge_agreement_json_body_params!
        vrp = agreement_vrp_from_credentials if agreement_credentials_present?
        if vrp == :invalid_credentials
          return render json: { success: false, message: "Invalid Jeevika Jankar username or password." }, status: :unauthorized
        end
        vrp ||= current_api_user if current_api_user.is_a?(Vrp)

        # The agreement terms are public form content. Allow the client to
        # render the first-login form before obtaining a JJ token; only the
        # acceptance action requires JJ authentication.
        render json: { success: true, agreement: agreement_payload(vrp.is_a?(Vrp) ? vrp : nil) }, status: :ok
      end

      # POST /api/v1/jeevika-jankar-agreement
      # Signs in the same request after acceptance, so mobile clients can enter
      # the app without first repeating their password login.
      def accept
        merge_agreement_json_body_params!
        credentials_present = agreement_credentials_present?
        vrp = credentials_present ? agreement_vrp_from_credentials : (current_api_user if current_api_user.is_a?(Vrp))
        return render json: { success: false, message: "Invalid Jeevika Jankar username or password." }, status: :unauthorized if vrp == :invalid_credentials
        return render json: { success: false, message: "Valid Jeevika Jankar login required." }, status: :unauthorized unless vrp.is_a?(Vrp)

        raw_signature = agreement_signature_param
        signature = normalized_agreement_signature(raw_signature)
        unless signature
          # Same message as before, plus what was wrong, so the app developer
          # can tell a missing field from an unreadable image.
          log_unreadable_signature(raw_signature)
          detail = if raw_signature.blank?
            "No signature was received. Send it as signature_data: a data:image/png;base64,... string, plain base64 of a PNG/JPEG, or an image file."
          else
            "The signature received is not a PNG, JPEG, WEBP or plain SVG drawing."
          end
          return render json: { success: false, message: "A valid digital signature is required. #{detail}",
                                error_code: raw_signature.blank? ? "signature_missing" : "signature_unreadable" },
                        status: :unprocessable_entity
        end

        if vrp.agreement_accepted?
          return render json: { success: false, message: "Agreement has already been accepted." }, status: :conflict
        end

        vrp.update!(agreement_accepted_at: Time.current, agreement_signature_data: signature)
        record_app_login(app_user_session_payload(vrp), :password)
        render json: {
          success: true, message: "Agreement accepted. You can now log in.",
          token: ApiAuthToken.encode(vrp), user: app_user_session_payload(vrp),
          agreement: agreement_payload(vrp.reload)
        }, status: :ok
      rescue ActiveRecord::RecordInvalid => error
        render json: { success: false, message: "Agreement could not be saved.", errors: error.record.errors.full_messages }, status: :unprocessable_entity
      end

      private

      SIGNATURE_DATA_URI = /\Adata:image\/(?:png|jpeg);base64,[A-Za-z0-9+\/=]+\z/
      # Names mobile clients use for the drawn signature, most common first.
      SIGNATURE_PARAM_KEYS = %i[signature_data signature signature_image digital_signature sign].freeze

      def agreement_signature_param
        SIGNATURE_PARAM_KEYS.lazy.map { |key| params[key] }.find(&:present?)
      end

      # Returns the signature as a PNG/JPEG/WEBP/SVG data URI, or nil when it is not one.
      # A value in the original strict format is kept exactly as sent. Mobile
      # clients also commonly send the base64 without the "data:" prefix, with
      # line breaks (Android Base64.DEFAULT), with "+" turned into spaces by
      # form encoding, URL-safe base64, or image/jpg; those are decoded and must
      # really be a PNG or JPEG image before they are accepted.
      def normalized_agreement_signature(raw)
        # An image sent as a multipart file upload.
        return signature_data_uri(raw.read.to_s.b) if raw.respond_to?(:read)

        value = raw.to_s.strip
        return value if value.match?(SIGNATURE_DATA_URI)
        return if value.blank?

        # Undo what a client may have wrapped it in: quotes, JSON escapes
        # ("\n", "\/") or percent-encoding ("%2B", "%2F", "%3D").
        value = value.delete_prefix('"').delete_suffix('"').gsub(/\\[nr]/, "").delete("\\")
        value = CGI.unescapeURIComponent(value) if value.match?(/%[0-9A-Fa-f]{2}/)
        # Any "data:...;base64," prefix (also with charset or other media types).
        value = value.sub(/\Adata:[^,]*,/i, "")

        body = value.tr(" ", "+").gsub(/\s+/, "").tr("-_", "+/")
        body += "=" * ((4 - body.length % 4) % 4)
        signature_data_uri(Base64.strict_decode64(body))
      rescue ArgumentError
        # The Android app draws the signature as SVG; plain SVG text is not base64.
        signature_data_uri(value.b) if value.lstrip.start_with?("<")
      end

      # What the app sent, without the signature itself, for the app developer.
      def log_unreadable_signature(raw)
        sample = raw.respond_to?(:read) ? "file #{raw.try(:content_type)} #{raw.try(:size)} bytes" : raw.to_s
        Rails.logger.warn(
          "[Agreement API] unreadable signature: class=#{raw.class} length=#{sample.length} " \
          "content_type=#{request.content_type} start=#{sample.first(40).inspect} end=#{sample.last(12).inspect}"
        )
      end

      def signature_data_uri(bytes)
        type = if bytes.start_with?("\x89PNG".b) then "png"
               elsif bytes.start_with?("\xFF\xD8\xFF".b) then "jpeg"
               elsif bytes.byteslice(0, 4) == "RIFF".b && bytes.byteslice(8, 4) == "WEBP".b then "webp"
               elsif drawn_svg_signature?(bytes) then "svg+xml"
               end
        "data:image/#{type};base64,#{Base64.strict_encode64(bytes)}" if type
      end

      SVG_SIGNATURE_ELEMENTS = %w[svg g path polyline polygon line circle ellipse rect title desc].freeze
      SVG_DRAWING_ELEMENTS = %w[path polyline polygon line circle ellipse rect].freeze
      SVG_SIGNATURE_MAX_BYTES = 1.megabyte

      # Accepts an SVG only when it is a plain drawing: shapes and lines, at
      # least one of them, and nothing that could run or load anything
      # (scripts, event handlers, links, external styles).
      def drawn_svg_signature?(bytes)
        return false if bytes.bytesize > SVG_SIGNATURE_MAX_BYTES

        text = bytes.dup.force_encoding(Encoding::UTF_8)
        return false unless text.valid_encoding?
        return false if text.match?(/<!DOCTYPE|<!ENTITY/i)

        root = REXML::Document.new(text).root
        return false unless root&.name == "svg"

        elements = [root]
        root.each_element("//*") { |element| elements << element }
        elements.all? do |element|
          SVG_SIGNATURE_ELEMENTS.include?(element.name) && element.attributes.each_attribute.none? do |attribute|
            name = attribute.expanded_name.downcase
            name.start_with?("on") || name.end_with?("href") || attribute.value.to_s.match?(/url\s*\(|javascript:/i)
          end
        end && elements.any? { |element| SVG_DRAWING_ELEMENTS.include?(element.name) }
      rescue REXML::ParseException
        false
      end

      def agreement_vrp_from_credentials
        login = params[:login].presence || params[:username].presence || params[:user_name].presence
        return unless login.present? || params[:password].present?

        AppUserAuthenticator.authenticate_vrp(login: login, password: params[:password]) || :invalid_credentials
      end

      def agreement_credentials_present?
        params[:username].present? || params[:user_name].present? || params[:login].present? || params[:password].present?
      end

      def merge_agreement_json_body_params!
        return unless request.body.present?

        body = request.raw_post.to_s
        return if body.blank?

        json = JSON.parse(body)
        json.each { |key, value| params[key] = value if params[key].blank? } if json.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def agreement_payload(vrp)
        accepted = vrp&.agreement_accepted? && vrp.agreement_signature_data.present?
        { required: !accepted, accepted: !!accepted,
          accepted_at: vrp&.agreement_accepted_at&.iso8601, name: vrp&.name.presence || vrp&.user_name || "-",
          village: vrp ? agreement_village_name(vrp) : "-", mobile_no: vrp&.mobile_no.presence || "-",
          date: Time.zone.today.strftime("%d/%m/%Y"), intro: AGREEMENT_TEXT[:intro],
          terms: AGREEMENT_TEXT[:terms], acceptance: AGREEMENT_TEXT[:acceptance],
          signature_data: vrp&.agreement_signature_data.presence }
      end

      def agreement_village_name(vrp)
        AgreementVillageName.call(vrp)
      end
    end
  end
end
