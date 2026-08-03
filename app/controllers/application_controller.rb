class ApplicationController < ActionController::Base
  include AppUserPayload

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_app_login

  helper_method :current_app_user

  private

  def send_xlsx(rows:, filename:, headers: nil, sheet_name: "Sheet1")
    data = if headers
      XlsxExporter.generate(headers: headers, rows: rows, sheet_name: sheet_name)
    else
      XlsxExporter.from_csv(rows, sheet_name: sheet_name)
    end

    xlsx_filename = filename.to_s.sub(/\.csv\z/i, ".xlsx")
    xlsx_filename = "#{xlsx_filename}.xlsx" unless xlsx_filename.downcase.end_with?(".xlsx")

    send_data data,
      filename: xlsx_filename,
      type: XlsxExporter::MIME_TYPE,
      disposition: "attachment"
  end

  def require_app_login
    redirect_to login_path, alert: "Please login first." unless current_app_user
  end

  def current_app_user
    return @current_app_user if defined?(@current_app_user)

    @current_app_user = refreshed_app_user_session
  end

  SESSION_REFRESH_INTERVAL = 15.minutes

  def refreshed_app_user_session
    stored_user = session[:app_user]
    return unless stored_user.present?

    if session_refresh_fresh?
      @current_app_user = stored_user
      return stored_user
    end

    user = find_current_session_user(stored_user)
    unless user
      @current_app_user = stored_user
      return stored_user
    end

    mark_session_refreshed!
    refresh_app_user_session!(user)
  end

  def session_refresh_fresh?
    refreshed_at = session[:app_user_refreshed_at]
    return false if refreshed_at.blank?

    Time.zone.parse(refreshed_at) > SESSION_REFRESH_INTERVAL.ago
  rescue ArgumentError, TypeError
    false
  end

  def mark_session_refreshed!
    session[:app_user_refreshed_at] = Time.current.iso8601
  end

  def refresh_app_user_session!(user)
    refreshed_user = app_user_session_payload(user)
    session[:app_user] = refreshed_user
    mark_session_refreshed!
    @current_app_user = refreshed_user
  end

  def find_current_session_user(stored_user)
    case stored_user["record_type"]
    when "User"
      return User.find_by(id: stored_user["id"]) if "User".safe_constantize&.table_exists?
    when "Vrp"
      return Vrp.find_by(id: stored_user["id"]) if "Vrp".safe_constantize&.table_exists?
    when "ModuleRecord"
      return ModuleRecord.where(module_slug: "new-user").find_by(id: stored_user["id"]) if defined?(ModuleRecord) && ModuleRecord.table_exists?
    end

    if "User".safe_constantize&.table_exists?
      user = User.find_by(id: stored_user["id"])
      return user if user

      user = User.find_by(user_name: stored_user["username"])
      return user if user
    end

    if "Vrp".safe_constantize&.table_exists? && Vrp.column_names.include?("user_name")
      vrp = Vrp.find_by(id: stored_user["id"])
      return vrp if vrp

      vrp = Vrp.find_by(user_name: stored_user["username"])
      return vrp if vrp
    end

    return unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    record = ModuleRecord.where(module_slug: "new-user").find_by(id: stored_user["id"])
    return record if record

    legacy_user_record_by_username(stored_user["username"].to_s)
  end

  def legacy_user_record_by_username(username)
    return if username.blank?

    @legacy_user_records_by_username ||= {}
    return @legacy_user_records_by_username[username] if @legacy_user_records_by_username.key?(username)

    @legacy_user_records_by_username[username] = ModuleRecord
      .where(module_slug: "new-user")
      .where("LOWER(data::jsonb ->> 'user_name') = ?", username.to_s.downcase)
      .order(created_at: :desc)
      .first
  end
end
