module Api
  module V1
    class JeevikaJankarApprovalsController < BaseController
      include VrpAccess

      def index
        rows = approval_queue.map { |vrp| approval_queue_row_payload(vrp) }

        render json: {
          success: true,
          message: "Jeevika Jankar approval queue fetched successfully.",
          approvals: rows,
          count: rows.size
        }, status: :ok
      end

      def approve
        merge_json_body_params!
        vrp = approvable_vrps.find { |record| record.id == params[:id].to_i }

        unless vrp
          return render json: {
            success: false,
            message: "This Jeevika Jankar is not pending for your approval."
          }, status: :forbidden
        end

        remarks = params[:remarks].to_s
        step = current_approval_step(vrp)
        next_sequence = next_approval_sequence(vrp)
        next_status = next_sequence.present? ? 29 + next_sequence : 55

        update_vrp_status!(vrp, next_status)
        log_approval_history(vrp, step, "Approved", remarks)

        message = if next_sequence.present?
          next_step = current_approval_step(vrp)
          "Approved and moved to #{approval_approver_name(next_step)}."
        else
          "Jeevika Jankar final approved."
        end

        render json: {
          success: true,
          message: message,
          jeevika_jankar: detail_payload(vrp)
        }, status: :ok
      end

      def reject
        merge_json_body_params!
        vrp = approvable_vrps.find { |record| record.id == params[:id].to_i }

        unless vrp
          return render json: {
            success: false,
            message: "This Jeevika Jankar is not pending for your approval."
          }, status: :forbidden
        end

        remarks = params[:remarks].to_s
        step = current_approval_step(vrp)
        update_vrp_status!(vrp, 99)
        log_approval_history(vrp, step, "Rejected", remarks)

        render json: {
          success: true,
          message: "Jeevika Jankar rejected.",
          jeevika_jankar: detail_payload(vrp)
        }, status: :ok
      end

      def return_record
        merge_json_body_params!
        vrp = approvable_vrps.find { |record| record.id == params[:id].to_i }

        unless vrp
          return render json: {
            success: false,
            message: "This Jeevika Jankar is not pending for your approval."
          }, status: :forbidden
        end

        remarks = params[:remarks].to_s
        step = current_approval_step(vrp)
        update_vrp_status!(vrp, 10)
        log_approval_history(vrp, step, "Returned", remarks)

        render json: {
          success: true,
          message: "Jeevika Jankar returned for correction.",
          jeevika_jankar: detail_payload(vrp)
        }, status: :ok
      end

      private

      def current_app_user
        current_api_user_payload
      end

      def merge_json_body_params!
        return if params[:remarks].present?
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
