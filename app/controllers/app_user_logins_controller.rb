# Who signed in from the Jeevika Jankar / staff mobile app, by date.
# Read-only; nothing here writes.
class AppUserLoginsController < ApplicationController
  PER_PAGE = 50
  EXPORT_HEADERS = [
    "#", "Date", "Time", "Name", "Username", "Type", "Role",
    "Office", "FCO", "Mobile", "Login By", "Device", "App Version", "IP"
  ].freeze

  def index
    load_filters
    scope = filtered_scope

    @total_count = scope.count
    @total_pages = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @summary = count_summary
  end

  # Exports exactly what the chosen date and search show.
  def export
    load_filters
    records = filtered_scope.limit(20_000).to_a

    send_xlsx(
      headers: EXPORT_HEADERS,
      rows: records.each_with_index.map { |record, index| export_row(record, index) },
      filename: "app-login-detail-#{export_filename_suffix}.xlsx",
      sheet_name: "App Login Detail"
    )
  end

  private

  # Names the file after what was exported, so a folder of them stays sorted
  # out: a day, a month, or everything.
  def export_filename_suffix
    case @view
    when "month" then @month.strftime("%B-%Y").downcase
    when "all" then "all-dates"
    else @date.strftime("%d-%m-%Y")
    end
  end

  # Day, month or everything. An unreadable date or month falls back to the
  # current one rather than silently widening to all time -- opening a page
  # on "everything" when you asked for a day is the worse surprise.
  def load_filters
    @search = params[:q].to_s.strip
    @kind = params[:kind].to_s.strip.presence_in(%w[Vrp User])
    @page = [params[:page].to_i, 1].max

    @view = params[:view].to_s.strip.presence_in(%w[day month all])
    @view ||= params[:month].present? ? "month" : "day"
    @view = "all" if params[:date].to_s.strip.casecmp("all").zero?

    case @view
    when "month"
      @month = (Date.parse("#{params[:month]}-01") rescue Date.current.beginning_of_month)
      @range = @month.all_month
      @range_label = @month.strftime("%B %Y")
    when "all"
      @range = nil
      @range_label = "all dates"
    else
      @date = (Date.parse(params[:date].to_s) rescue Date.current)
      @range = @date.all_day
      @range_label = @date.strftime("%d %B %Y")
    end
  end

  # Carries the active range through links so a filter, a page or the export
  # never silently jumps back to today.
  def range_params
    case @view
    when "month" then { view: "month", month: @month.strftime("%Y-%m") }
    when "all" then { view: "all" }
    else { view: "day", date: @date.to_s }
    end
  end
  helper_method :range_params

  def filtered_scope
    scope = AppUserLogin.recent_first
    scope = scope.where(logged_in_at: @range) if @range
    scope = scope.where(record_type: @kind) if @kind
    scope = apply_search(scope) if @search.present?
    scope
  end

  # Both counters in one trip rather than two sequential reads.
  def count_summary
    sql = <<~SQL.squish
      SELECT COUNT(*) AS logins,
             COUNT(DISTINCT (record_type || ':' || record_id)) AS people,
             COUNT(DISTINCT (record_type || ':' || record_id))
               FILTER (WHERE record_type = 'Vrp') AS jeevika_jankars,
             COUNT(DISTINCT (record_type || ':' || record_id))
               FILTER (WHERE record_type <> 'Vrp') AS staff
      FROM app_user_logins
    SQL
    sql += " WHERE logged_in_at >= :from AND logged_in_at <= :to" if @range

    row = AppUserLogin.connection.select_one(
      AppUserLogin.sanitize_sql_array([sql, { from: @range&.first, to: @range&.last }])
    ) || {}

    {
      logins: row["logins"].to_i,
      people: row["people"].to_i,
      jeevika_jankars: row["jeevika_jankars"].to_i,
      staff: row["staff"].to_i
    }
  end

  def export_row(record, index)
    [
      index + 1,
      record.logged_in_at&.in_time_zone&.strftime("%d-%m-%Y"),
      record.logged_in_at&.in_time_zone&.strftime("%I:%M %p"),
      record.name, record.username, record.user_kind, record.role,
      record.office_name, record.fcoc,
      # Masked in the sheet too: an export travels further than the screen.
      record.masked_mobile,
      record.login_method == "otp" ? "OTP" : "Password",
      record.device, record.app_version, record.ip
    ]
  end

  def apply_search(scope)
    clauses = %w[name username role office_name fcoc]
      .map { |column| "LOWER(COALESCE(#{column}, '')) LIKE :term" }
    binds = { term: "%#{@search.downcase}%" }

    digits = @search.gsub(/\D/, "")
    if digits.present?
      clauses << "regexp_replace(COALESCE(mobile_no, ''), '[^0-9]', '', 'g') LIKE :digits"
      binds[:digits] = "%#{digits}%"
    end

    scope.where(clauses.join(" OR "), **binds)
  end
end
