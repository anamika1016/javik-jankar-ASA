module Api
  module V1
    class JeevikaJankarsController < BaseController
      include VrpAccess

      def index
        records = visible_vrps.map { |vrp| list_row_payload(vrp) }

        render json: {
          success: true,
          message: "Jeevika Jankar list fetched successfully.",
          jeevika_jankars: records,
          count: records.size
        }, status: :ok
      end

      def show
        vrp = find_api_visible_vrp(params[:id])
        unless vrp
          return render json: { success: false, message: "Jeevika Jankar record not found." }, status: :not_found
        end

        render json: {
          success: true,
          jeevika_jankar: detail_payload(vrp)
        }, status: :ok
      end

      def create
        merge_json_body_params!
        attrs = jeevika_jankar_attributes

        vrp = Vrp.new(attrs)
        vrp.created_by_id = current_app_user_id if vrp.respond_to?(:created_by_id=)
        vrp.created_by_type = current_app_user&.dig("record_type") if vrp.respond_to?(:created_by_type=)
        vrp.status = 10 if vrp.respond_to?(:status=)
        apply_current_identity_to_vrp(vrp)

        unless password_confirmed?(vrp)
          return render json: {
            success: false,
            message: "Password and Confirm Password must match.",
            errors: [ "Password and Confirm Password must match" ]
          }, status: :unprocessable_entity
        end

        if vrp.save
          render json: {
            success: true,
            message: "Jeevika Jankar registration successful.",
            jeevika_jankar: detail_payload(vrp)
          }, status: :created
        else
          render json: {
            success: false,
            message: "Jeevika Jankar registration failed.",
            errors: vrp.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def update
        merge_json_body_params!
        vrp = find_api_manageable_vrp(params[:id])
        unless vrp
          return render json: { success: false, message: "Jeevika Jankar record not found or you cannot edit it." }, status: :not_found
        end

        attrs = jeevika_jankar_attributes(for_update: true)
        unless update_password_confirmed?(attrs)
          return render json: {
            success: false,
            message: "Password and Confirm Password must match.",
            errors: [ "Password and Confirm Password must match" ]
          }, status: :unprocessable_entity
        end

        vrp.assign_attributes(attrs)
        if vrp.save
          render json: {
            success: true,
            message: "Jeevika Jankar updated successfully.",
            jeevika_jankar: detail_payload(vrp)
          }, status: :ok
        else
          render json: {
            success: false,
            message: "Jeevika Jankar update failed.",
            errors: vrp.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def form_options
        render json: {
          success: true,
          options: form_options_payload
        }, status: :ok
      end

      def send_for_approval
        vrp = own_vrps.find_by(id: params[:id])
        unless vrp
          return render json: { success: false, message: "Jeevika Jankar record not found." }, status: :not_found
        end

        steps = approval_steps_for(vrp)
        first_step = steps.first
        unless first_step
          return render json: {
            success: false,
            message: "Approval channel is not configured for your role."
          }, status: :unprocessable_entity
        end

        if approval_sent?(vrp) || [ 31, 32, 55 ].include?(vrp.status.to_i)
          return render json: {
            success: false,
            message: "This Jeevika Jankar is already in approval process."
          }, status: :unprocessable_entity
        end

        update_vrp_status!(vrp, 25)
        log_approval_history(vrp, first_step, "Sent for Approval", "Pending at #{approval_approver_name(first_step)}")

        render json: {
          success: true,
          message: "Jeevika Jankar sent for approval. Pending at #{approval_approver_name(first_step)}.",
          jeevika_jankar: detail_payload(vrp)
        }, status: :ok
      end

      private

      def current_app_user
        current_api_user_payload
      end

      def find_api_visible_vrp(id)
        (visible_vrps.to_a + approval_queue).uniq.find { |vrp| vrp.id == id.to_i }
      end

      def find_api_manageable_vrp(id)
        if current_app_user&.dig("record_type") == "Vrp"
          return Vrp.find_by(id: id, is_deleted: false) if current_app_user_id.to_i == id.to_i

          return nil
        end

        find_manageable_vrp(id)
      end

      def update_password_confirmed?(attrs)
        return true unless attrs.key?(:password) && attrs[:password].present?

        confirmed = params[:confirmed_password].presence ||
          params.dig(:vrp, :confirmed_password).presence ||
          params.dig(:jeevika_jankar, :confirmed_password).to_s
        attrs[:password].to_s == confirmed.to_s
      end

      def password_confirmed?(vrp)
        confirmed = params[:confirmed_password].presence ||
          params.dig(:vrp, :confirmed_password).presence ||
          params.dig(:jeevika_jankar, :confirmed_password).to_s
        return true if vrp.password.to_s.blank? && confirmed.to_s.blank?

        vrp.password.to_s == confirmed.to_s
      end

      def jeevika_jankar_attributes(for_update: false)
        raw = params[:jeevika_jankar].presence || params[:vrp].presence || params
        permitted = raw.permit(
          :name,
          :father_husband_name,
          :gender,
          :date_of_birth,
          :date_of_joining,
          :aadhar_no,
          :account_no,
          :bank_name,
          :branch,
          :ifsc_code,
          :vrp_bank_master_id,
          :address,
          :mobile_no,
          :emergency_no,
          :email,
          :fcoc,
          :to_name,
          :cluster_incharge,
          :stakeholder,
          :stakeholder_role,
          :role,
          :user_management_role,
          :person_type,
          :user_name,
          :password,
          :experience_in_years,
          :user_id,
          :is_active,
          :photo,
          :aadhar_upload,
          :bank_passbook_upload,
          project_master_ids: [],
          ics_master_ids: [],
          vrp_type_ids: [],
          village_ids: [],
          gram_panchayat_ids: [],
          vrp_profile_attributes: [
            :id,
            :state_id,
            :district_id,
            :block_id,
            :gram_panchayat_id,
            :village_id,
            :vrp_id,
            :_destroy
          ]
        )

        # Flat profile fields from React Native forms
        if permitted[:vrp_profile_attributes].blank?
          profile = {
            state_id: raw[:state_id],
            district_id: raw[:district_id],
            block_id: raw[:block_id],
            gram_panchayat_id: raw[:gram_panchayat_id],
            village_id: raw[:village_id]
          }.compact
          permitted[:vrp_profile_attributes] = profile if profile.present?
        end

        permitted[:email] = permitted[:email].presence || "" unless for_update
        permitted
      end

      def merge_json_body_params!
        return if params[:name].present? || params[:jeevika_jankar].present? || params[:vrp].present?
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
