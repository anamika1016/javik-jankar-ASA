module Api
  module V1
    # GET /api/v1/accepted-agreements      list (q, page, per_page)
    # GET /api/v1/accepted-agreements/:id  one agreement, with its signature
    #
    # The same rows, search and visibility as the web page "Accepted Agreement
    # by Jeevika Jankar": an admin sees every agreement, a Jeevika Jankar only
    # their own, other staff the Jeevika Jankars mapped to them.
    class AcceptedAgreementsController < BaseController
      def index
        rows = AcceptedAgreementList.search(AcceptedAgreementList.new(visible_vrps).rows, params[:q])
        page_rows = rows.slice((page_number - 1) * per_page, per_page) || []

        render json: {
          success: true,
          message: "Accepted agreements fetched successfully.",
          accepted_agreements: page_rows.map { |row| row_payload(row) },
          count: page_rows.size,
          total_count: rows.size,
          page: page_number,
          per_page: per_page
        }, status: :ok
      end

      def show
        vrp = visible_vrps.where.not(agreement_accepted_at: nil).find_by(id: params[:id])
        unless vrp
          return render json: { success: false, message: "Signed agreement not found." }, status: :not_found
        end

        row = AcceptedAgreementList.new(Vrp.where(id: vrp.id)).rows.first
        render json: {
          success: true,
          accepted_agreement: row_payload(row).merge(
            signature_data: vrp.agreement_signature_data.presence,
            agreement: Api::V1::VrpAgreementsController::AGREEMENT_TEXT
          )
        }, status: :ok
      end

      private

      def visible_vrps
        AcceptedAgreementList.visible_vrps(current_api_user_payload, request: request)
      end

      def row_payload(row)
        {
          id: row[:id],
          name: row[:name],
          fco_name: row[:fcoc],
          to_name: row[:to_name],
          village: row[:village],
          mobile_number: row[:mobile_no],
          accepted_at: row[:accepted_at],
          accepted_at_iso: row[:accepted_at_iso],
          signature: row[:signature_present] ? "Signed" : "Signature missing",
          signature_present: !!row[:signature_present]
        }
      end

      def page_number
        [params[:page].to_i, 1].max
      end

      def per_page
        requested = params[:per_page].to_i
        requested = 100 if requested <= 0
        requested.clamp(1, 1_000)
      end
    end
  end
end
