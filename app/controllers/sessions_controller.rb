require "securerandom"

class SessionsController < ApplicationController
  skip_before_action :require_app_login
  helper_method :agreement_details
  FORGOT_PASSWORD_OTP_TTL = 10.minutes

  def new
    redirect_to dashboard_path if current_app_user
  end

  def create
    user = find_app_user

    if user
      if vrp_agreement_required?(user)
        reset_session
        session[:pending_vrp_agreement_id] = user.id
        redirect_to vrp_agreement_path
        return
      end

      reset_session
      refresh_app_user_session!(user)
      redirect_to dashboard_path, notice: "Logged in successfully."
    else
      redirect_to login_path, alert: "Invalid username or password."
    end
  end

  def agreement
    @vrp = pending_vrp_agreement

    unless @vrp
      redirect_to login_path, alert: "Please login again to continue."
      return
    end

    @agreement_details = agreement_details(@vrp)
  end

  def complete_agreement
    @vrp = pending_vrp_agreement

    unless @vrp
      redirect_to login_path, alert: "Please login again to continue."
      return
    end

    if params[:decision] == "agree"
      signature_data = params[:signature_data].to_s.strip
      if signature_data.blank?
        @agreement_details = agreement_details(@vrp)
        flash.now[:alert] = "Please sign before accepting the declaration."
        render :agreement, status: :unprocessable_entity
        return
      end

      @vrp.update!(agreement_accepted_at: Time.current, agreement_signature_data: signature_data)
      reset_session
      refresh_app_user_session!(@vrp)
      redirect_to dashboard_path, notice: "Logged in successfully."
    else
      reset_session
      redirect_to login_path, alert: "Declaration declined. Login is allowed only after accepting the declaration."
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out successfully."
  end

  def forgot_password
    @forgot_username = params[:username].to_s
  end

  def send_forgot_password_otp
    @forgot_username = params[:username].to_s.strip
    account = find_password_reset_account(@forgot_username)

    if account.blank?
      clear_password_reset_session
      render_forgot_password_response("Username not matched. OTP not sent.", status: :unprocessable_entity, alert: true)
      return
    end

    mobile_number = reset_account_mobile(account)
    if mobile_number.blank?
      clear_password_reset_session
      render_forgot_password_response("Registered mobile number not found. OTP not sent.", status: :unprocessable_entity, alert: true)
      return
    end

    otp = SecureRandom.random_number(10_000).to_s.rjust(4, "0")
    session[:password_reset] = {
      "record_type" => reset_account_type(account),
      "record_id" => account.id,
      "username" => @forgot_username,
      "otp" => otp,
      "expires_at" => FORGOT_PASSWORD_OTP_TTL.from_now.iso8601
    }

    sms_result = OtpSmsSender.new(mobile_number, otp).deliver
    unless sms_result.success?
      clear_password_reset_session
      render_forgot_password_response(
        forgot_password_sms_error_message(sms_result),
        status: :unprocessable_entity,
        alert: true,
        sms: sms_result
      )
      return
    end

    render_forgot_password_response(
      "OTP sent to registered mobile number.",
      status: :ok,
      sms: sms_result
    )
  end

  def reset_forgot_password
    @forgot_username = params[:username].to_s.strip
    account = password_reset_session_account

    unless account && password_reset_session_valid_for?(@forgot_username)
      clear_password_reset_session
      render_forgot_password_response("OTP expired or username not matched. Please get OTP again.", status: :unprocessable_entity, alert: true)
      return
    end

    if params[:otp_code].to_s.strip != session.dig(:password_reset, "otp").to_s
      render_forgot_password_response("Invalid OTP code.", status: :unprocessable_entity, alert: true)
      return
    end

    password = params[:password].to_s
    confirmed_password = params[:confirmed_password].to_s
    if password.blank? || password != confirmed_password
      render_forgot_password_response("Password and Confirm Password must match.", status: :unprocessable_entity, alert: true)
      return
    end

    update_reset_account_password!(account, password)
    clear_password_reset_session
    redirect_to login_path, notice: "Password reset successfully. Please sign in."
  end

  private

  def pending_vrp_agreement
    return unless "Vrp".safe_constantize&.table_exists?
    return unless Vrp.column_names.include?("agreement_accepted_at")

    Vrp.where(is_active: true, is_deleted: false).find_by(id: session[:pending_vrp_agreement_id])
  end

  def vrp_agreement_required?(user)
    user.is_a?(Vrp) &&
      Vrp.column_names.include?("agreement_accepted_at") &&
      !user.agreement_accepted?
  end

  def agreement_details(vrp)
    return {} unless vrp

    {
      name: vrp.name.presence || vrp.user_name.presence || "-",
      village: agreement_village_name(vrp),
      mobile_no: vrp.mobile_no.presence || "-",
      date: Time.zone.today.strftime("%d/%m/%Y")
    }
  end

  def agreement_village_name(vrp)
    village_id = agreement_primary_village_id(vrp)
    return "-" if village_id.blank?

    village_name = agreement_village_label(village_id)
    return village_name if village_name.present?

    village_id.to_s
  end

  def agreement_primary_village_id(vrp)
    return vrp.vrp_profile.village_id if vrp.respond_to?(:vrp_profile) && vrp.vrp_profile&.village_id.present?

    Array(vrp.village_ids).map(&:to_s).reject(&:blank?).first
  end

  def agreement_village_label(village_id)
    [
      agreement_village_name_from_module_records(village_id),
      agreement_village_name_from_target_mapping(village_id),
      agreement_village_name_from_vrp_ics_mapping(village_id),
      agreement_village_name_from_afl(village_id)
    ].compact_blank.first.to_s
  end

  def agreement_village_name_from_afl(village_id)
    return unless defined?(Afl) && Afl.table_exists?

    Afl.where(village_id: village_id.to_s).order(:village_name, :id).limit(1).pick(:village_name).presence
  end

  def agreement_village_name_from_target_mapping(village_id)
    return unless defined?(TargetMapping) && TargetMapping.table_exists?

    TargetMapping.where(village_id: village_id.to_s).order(:village_name, :id).limit(1).pick(:village_name).presence
  end

  def agreement_village_name_from_vrp_ics_mapping(village_id)
    return unless defined?(VrpIcsMapping) && VrpIcsMapping.table_exists?

    VrpIcsMapping.where(village_id: village_id.to_s).order(:village_name, :id).limit(1).pick(:village_name).presence
  end

  def agreement_village_name_from_module_records(village_id)
    return unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    record = ModuleRecord.find_by(id: village_id) ||
      ModuleRecord.where(id: village_id).find_by(module_slug: "village-master") ||
      ModuleRecord.where(id: village_id).find_by(module_slug: "lg-directory-list")
    return unless record

    if record.respond_to?(:data)
      [
        record.data["village_name"],
        record.data["village"],
        record.data["name"],
        record.data["title"]
      ].compact_blank.first.presence
    end
  end

  def find_app_user
    AppUserAuthenticator.authenticate(
      login: params[:login].presence || params[:email].presence,
      password: params[:password]
    )
  end

  def find_password_reset_account(username)
    return if username.blank?
    username_key = username.to_s.strip.downcase

    if "User".safe_constantize&.table_exists?
      user = User.where.not(status: "Inactive")
        .where("LOWER(user_name) = ?", username_key)
        .first
      return user if user
    end

    if "Vrp".safe_constantize&.table_exists? && Vrp.column_names.include?("user_name")
      vrp = Vrp.where(is_active: true, is_deleted: false)
        .where("LOWER(user_name) = ?", username_key)
        .first
      return vrp if vrp
    end

    return unless module_record_auth_ready?

    ModuleRecord.where(module_slug: "new-user").find_each do |record|
      next unless module_record_active_for_login?(record)

      return record if module_record_value(record, "user_name").to_s.downcase == username_key
    end

    nil
  rescue StandardError => e
    Rails.logger.warn("Password reset lookup failed: #{e.class} - #{e.message}")
    nil
  end

  def module_record_auth_ready?
    defined?(ModuleRecord) && ModuleRecord.respond_to?(:table_exists?) && ModuleRecord.table_exists?
  rescue StandardError
    false
  end

  def module_record_active_for_login?(record)
    module_record_value(record, "status").to_s.downcase != "inactive"
  end

  def module_record_value(record, key)
    data = record.respond_to?(:data) ? record.data : {}
    data = JSON.parse(data) if data.is_a?(String)
    return unless data.respond_to?(:[])

    data[key] || data[key.to_sym]
  rescue JSON::ParserError
    nil
  end

  def reset_account_type(account)
    account.is_a?(ModuleRecord) ? "ModuleRecord" : account.class.name
  end

  def reset_account_mobile(account)
    account.respond_to?(:mobile_no) ? account.mobile_no : account.data["mobile_no"]
  end

  def password_reset_session_account
    reset_data = session[:password_reset]
    return if reset_data.blank?

    case reset_data["record_type"]
    when "User"
      User.find_by(id: reset_data["record_id"]) if "User".safe_constantize&.table_exists?
    when "Vrp"
      Vrp.find_by(id: reset_data["record_id"]) if "Vrp".safe_constantize&.table_exists?
    when "ModuleRecord"
      ModuleRecord.where(module_slug: "new-user").find_by(id: reset_data["record_id"]) if defined?(ModuleRecord) && ModuleRecord.table_exists?
    end
  end

  def password_reset_session_valid_for?(username)
    reset_data = session[:password_reset]
    return false if reset_data.blank?
    return false if username.blank? || reset_data["username"].to_s != username

    expires_at = Time.iso8601(reset_data["expires_at"].to_s)
    expires_at.future?
  rescue ArgumentError
    false
  end

  def update_reset_account_password!(account, password)
    if account.is_a?(ModuleRecord)
      account.update!(data: account.data.merge("password" => password, "confirmed_password" => password))
    else
      account.update_column(:password, password)
    end
  end

  def clear_password_reset_session
    session.delete(:password_reset)
  end

  def render_forgot_password_response(message, status:, alert: false, sms: nil)
    respond_to do |format|
      format.html do
        flash.now[alert ? :alert : :notice] = message
        render :forgot_password, status: status
      end

      format.json do
        render json: forgot_password_response_body(message, alert: alert, sms: sms), status: status
      end
    end
  end

  def forgot_password_response_body(message, alert:, sms:)
    body = {
      success: !alert,
      message: message,
      username: @forgot_username
    }

    if sms
      body[:sms] = {
        message: sms.message,
        response_code: sms.response_code,
        response_body: sms.response_body
      }.compact
    end

    body
  end

  def forgot_password_sms_error_message(sms_result)
    reason = sms_result.message.to_s.strip
    reason = "#{reason}." if reason.present? && !reason.match?(/[.!?]\z/)

    ["OTP could not be sent.", reason.presence, "Please try again."].compact.join(" ")
  end
end
