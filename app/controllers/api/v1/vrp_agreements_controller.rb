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

        signature = params[:signature_data].to_s.strip
        unless signature.match?(/\Adata:image\/(?:png|jpeg);base64,[A-Za-z0-9+\/=]+\z/)
          return render json: { success: false, message: "A valid digital signature is required." }, status: :unprocessable_entity
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
