require "csv"

class VrpAgreementsController < ApplicationController
  layout :agreement_layout
  helper_method :agreement_admin_user?

  def index
    @accepted_agreements = accepted_agreement_rows
  end

  def export
    rows = accepted_agreement_rows
    send_xlsx(
      headers: ["Name", "Village", "FCO Name", "Mobile Number", "Accepted At", "Signature"],
      rows: rows.map do |agreement|
        [
          agreement[:name],
          agreement[:village],
          agreement[:fcoc],
          agreement[:mobile_no],
          agreement[:accepted_at].presence || "-",
          agreement[:signature_present] ? "Signed" : "Pending"
        ]
      end,
      filename: "accepted-agreements-jeevika-jankar-#{Time.zone.today}.xlsx",
      sheet_name: "Accepted Agreements"
    )
  end

  def show
    @vrp = Vrp.find_by(id: params[:id])
    unless @vrp&.agreement_accepted?
      redirect_to vrp_agreements_path, alert: "Signed agreement not found."
      return
    end

    @agreement_details = agreement_details(@vrp)
  end

  def destroy
    @vrp = Vrp.find_by(id: params[:id])
    unless @vrp
      redirect_to vrp_agreements_path, alert: "Agreement not found."
      return
    end

    @vrp.update!(agreement_accepted_at: nil, agreement_signature_data: nil)
    redirect_to vrp_agreements_path, notice: "Agreement deleted. Jeevika Jankar must sign again on next login."
  end

  private

  def accepted_agreement_rows
    return [] unless vrp_agreement_enabled?

    scope = agreement_visible_vrps
      .includes(:vrp_profile)
      .select(:id, :name, :user_name, :mobile_no, :fcoc, :agreement_accepted_at, :agreement_signature_data, :village_ids)
      .where.not(agreement_accepted_at: nil)
      .where.not(agreement_signature_data: [nil, ""])
      .order(agreement_accepted_at: :desc)

    scope.map do |vrp|
        {
          id: vrp.id,
          name: vrp.name.presence || vrp.user_name.presence || "-",
          village: agreement_village_name(vrp),
          fcoc: vrp.fcoc.presence || "-",
          mobile_no: vrp.mobile_no.presence || "-",
          accepted_at: vrp.agreement_accepted_at&.strftime("%d/%m/%Y %I:%M %p"),
          signature_present: vrp.agreement_signature_data.present?
        }
      end
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
    AgreementVillageName.call(vrp)
  end

  def vrp_agreement_enabled?
    defined?(Vrp) && Vrp.table_exists? && Vrp.column_names.include?("agreement_accepted_at")
  end

  def agreement_layout
    action_name == "show" ? "agreement_pdf" : "application"
  end

  def agreement_admin_user?
    current_app_user&.dig("user_type").to_s.casecmp("admin").zero?
  end

  def agreement_visible_vrps
    return Vrp.all if current_app_user.blank? || agreement_admin_user?

    user_id = current_app_user&.dig("id")
    username = current_app_user&.dig("username").to_s
    email = current_app_user&.dig("email").to_s.downcase.presence

    ids = [user_id].compact
    if username.present? && defined?(User) && User.table_exists?
      user = User.find_by(user_name: username)
      ids << user.id if user
    end
    ids = ids.compact.uniq

    scope = Vrp.none
    if ids.any?
      scope = scope.or(Vrp.where(created_by_id: ids))
      scope = scope.or(Vrp.where(user_id: ids)) if Vrp.column_names.include?("user_id")
    end

    if email.present?
      unassigned = Vrp.where(created_by_id: nil).where("LOWER(email) = ?", email)
      unassigned = unassigned.where(user_id: nil) if Vrp.column_names.include?("user_id")
      scope = scope.or(unassigned)
    end

    vrp_record = Vrp.find_by(user_name: username) if username.present?
    scope = scope.or(Vrp.where(id: vrp_record.id)) if vrp_record

    scope
  end
end
