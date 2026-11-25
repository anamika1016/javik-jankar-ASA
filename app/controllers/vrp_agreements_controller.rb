require "csv"

class VrpAgreementsController < ApplicationController
  before_action :refresh_agreement_user_mapping
  layout :agreement_layout
  helper_method :agreement_admin_user?

  def index
    @search = params[:q].to_s.strip
    @accepted_agreements = search_agreements(accepted_agreement_rows, @search)
  end

  def export
    rows = search_agreements(accepted_agreement_rows, params[:q].to_s.strip)
    send_xlsx(
      headers: ["Name", "Village", "FCO Name", "TO Name", "Mobile Number", "Accepted At", "Signature"],
      rows: rows.map do |agreement|
        [
          agreement[:name],
          agreement[:village],
          agreement[:fcoc],
          agreement[:to_name],
          agreement[:mobile_no],
          agreement[:accepted_at].presence || "-",
          agreement[:signature_present] ? "Signed" : "Signature missing"
        ]
      end,
      filename: "accepted-agreements-jeevika-jankar-#{Time.zone.today}.xlsx",
      sheet_name: "Accepted Agreements"
    )
  end

  def show
    @vrp = agreement_visible_vrps.find_by(id: params[:id])
    unless @vrp&.agreement_accepted?
      redirect_to vrp_agreements_path, alert: "Signed agreement not found."
      return
    end

    @agreement_details = agreement_details(@vrp)
  end

  def destroy
    @vrp = agreement_visible_vrps.find_by(id: params[:id])
    unless @vrp
      redirect_to vrp_agreements_path, alert: "Agreement not found."
      return
    end

    @vrp.update!(agreement_accepted_at: nil, agreement_signature_data: nil)
    redirect_to vrp_agreements_path, notice: "Agreement deleted. Jeevika Jankar must sign again on next login."
  end

  private

  def search_agreements(rows, term)
    AcceptedAgreementList.search(rows, term)
  end

  def accepted_agreement_rows
    list = AcceptedAgreementList.new(agreement_visible_vrps)
    rows = list.rows
    @agreement_village_resolver = list.village_resolver
    rows
  end

  def agreement_details(vrp)
    return {} unless vrp

    {
      name: vrp.name.presence || vrp.user_name.presence || "-",
      village: agreement_village_name(vrp),
      mobile_no: vrp.mobile_no.presence || "-",
      date: vrp.agreement_accepted_at&.strftime("%d/%m/%Y") || Time.zone.today.strftime("%d/%m/%Y")
    }
  end

  def agreement_village_name(vrp)
    @agreement_village_resolver ? @agreement_village_resolver.call(vrp) : AgreementVillageName.call(vrp)
  end

  def agreement_layout
    action_name == "show" ? "agreement_pdf" : "application"
  end

  def agreement_admin_user?
    current_app_user&.dig("user_type").to_s.strip.casecmp("admin").zero?
  end

  # Office and role edits must apply immediately, even with an existing login.
  def refresh_agreement_user_mapping
    user = find_current_session_user(current_app_user) if current_app_user.present?
    refresh_app_user_session!(user) if user
  end

  def agreement_visible_vrps
    AcceptedAgreementList.visible_vrps(current_app_user, request: request)
  end
end
