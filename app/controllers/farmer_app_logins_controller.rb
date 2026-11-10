# Web list of farmers who have signed in from the Android app. Read-only.
#
# Two modes. By date (the default, today) the list reads login events, so a
# farmer appears under every date they signed in. "All dates" falls back to
# one row per farmer showing their latest sign-in.
class FarmerAppLoginsController < ApplicationController
  PER_PAGE = 50
  EXPORT_HEADERS = [
    "#", "Farmer Name", "Father / Husband", "Mobile", "Aadhaar", "Logged in With",
    "Village", "District", "State", "FCO", "ICS", "Tracenet", "Logins",
    "First Login", "Last Login", "Last OTP Status", "Last OTP Sent",
    "Wrong OTP Attempts", "Account Locked", "Device", "App Version", "IP", "Location",
    "Latitude", "Longitude"
  ].freeze

  def index
    load_filters
    scope = filtered_scope

    @records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    load_related(@records)

    @total_count = filtered_count
    @total_pages = [(@total_count / PER_PAGE.to_f).ceil, 1].max
    @summary = count_summary
  end

  # Exports exactly what the current date, search and filter show.
  def export
    load_filters
    records = filtered_scope.limit(20_000).to_a
    load_related(records)

    send_xlsx(
      headers: EXPORT_HEADERS,
      rows: records.each_with_index.map { |record, index| export_row(record, index) },
      filename: "farmer-app-logins-#{export_filename_suffix}.xlsx",
      sheet_name: "Farmer App Logins"
    )
  end

  private

  def load_filters
    @search = params[:q].to_s.strip
    @method_filter = params[:method].to_s.strip.presence_in(FarmerAppLogin::IDENTIFIER_TYPES)
    @page = [params[:page].to_i, 1].max
    @all_dates = params[:date].to_s.strip.casecmp("all").zero?
    # Today unless a date was picked; an unparseable date falls back to today
    # rather than silently showing everything.
    @date = @all_dates ? nil : (Date.parse(params[:date].to_s) rescue Date.current)
  end

  def filtered_scope
    @all_dates ? all_dates_scope : date_scope
  end

  # One row per farmer who signed in on the chosen date. The day's own count,
  # time, method and device come back as aggregates so the view needs no
  # further query per row.
  def date_scope
    scope = FarmerAppLogin
      .joins(:login_events)
      .where(farmer_app_login_events: { logged_in_at: @date.all_day })
      .group("farmer_app_logins.id")
      .select(<<~SQL.squish)
        farmer_app_logins.*,
        COUNT(farmer_app_login_events.id) AS day_login_count,
        MAX(farmer_app_login_events.logged_in_at) AS day_last_login,
        MIN(farmer_app_login_events.logged_in_at) AS day_first_login,
        (ARRAY_AGG(farmer_app_login_events.identifier_type
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_identifier_type,
        (ARRAY_AGG(farmer_app_login_events.ip
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_ip,
        (ARRAY_AGG(farmer_app_login_events.device
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_device,
        (ARRAY_AGG(farmer_app_login_events.app_version
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_app_version,
        (ARRAY_AGG(farmer_app_login_events.place
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_place,
        (ARRAY_AGG(farmer_app_login_events.latitude
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_latitude,
        (ARRAY_AGG(farmer_app_login_events.longitude
          ORDER BY farmer_app_login_events.logged_in_at DESC))[1] AS day_longitude
      SQL
    scope = scope.where(farmer_app_login_events: { identifier_type: @method_filter }) if @method_filter
    scope = apply_search(scope) if @search.present?
    scope.order(Arel.sql("MAX(farmer_app_login_events.logged_in_at) DESC"))
  end

  def all_dates_scope
    scope = FarmerAppLogin.recent_first
    scope = scope.where(last_identifier_type: @method_filter) if @method_filter
    scope = apply_search(scope) if @search.present?
    scope
  end

  def filtered_count
    return all_dates_scope.count if @all_dates

    # A grouped relation counts per group and returns a hash; the page needs
    # how many groups there are, so the grouping is dropped for the count.
    date_scope.unscope(:select, :order, :group).count("DISTINCT farmer_app_logins.id")
  end

  # Two batch lookups for the whole set, never one per row.
  def load_related(records)
    mobiles = records.map(&:mobile_no).compact_blank.uniq
    @otp_status = latest_otp_by_mobile(mobiles)
    @locks = mobiles.any? ? FarmerLoginLock.where(mobile_no: mobiles).index_by(&:mobile_no) : {}
  end

  # Counters for the tiles. On a date they describe that date; across all
  # dates they describe the whole table.
  def count_summary
    return all_dates_summary unless @date

    row = FarmerAppLogin.connection.select_one(
      FarmerAppLogin.sanitize_sql_array([
        <<~SQL.squish,
          SELECT COUNT(DISTINCT farmer_app_login_id) AS farmers,
                 COUNT(*) AS logins,
                 COUNT(DISTINCT farmer_app_login_id) FILTER (WHERE identifier_type = 'mobile') AS mobile,
                 COUNT(DISTINCT farmer_app_login_id) FILTER (WHERE identifier_type = 'aadhaar') AS aadhaar
          FROM farmer_app_login_events
          WHERE logged_in_at >= :from AND logged_in_at < :to
        SQL
        { from: @date.beginning_of_day, to: @date.end_of_day }
      ])
    ) || {}

    {
      farmers: row["farmers"].to_i,
      logins: row["logins"].to_i,
      mobile: row["mobile"].to_i,
      aadhaar: row["aadhaar"].to_i,
      farmers_label: "Farmers on this date",
      logins_label: "Total Logins"
    }
  end

  def all_dates_summary
    row = FarmerAppLogin.connection.select_one(
      FarmerAppLogin.sanitize_sql_array([
        <<~SQL.squish,
          SELECT COUNT(*) AS farmers,
                 COUNT(*) FILTER (WHERE last_logged_in_at >= :from AND last_logged_in_at < :to) AS logins,
                 COUNT(*) FILTER (WHERE last_identifier_type = 'mobile') AS mobile,
                 COUNT(*) FILTER (WHERE last_identifier_type = 'aadhaar') AS aadhaar
          FROM farmer_app_logins
        SQL
        { from: Time.zone.now.beginning_of_day, to: Time.zone.now.end_of_day }
      ])
    ) || {}

    {
      farmers: row["farmers"].to_i,
      logins: row["logins"].to_i,
      mobile: row["mobile"].to_i,
      aadhaar: row["aadhaar"].to_i,
      farmers_label: "Total Farmers",
      logins_label: "Logged in Today"
    }
  end

  def export_filename_suffix
    return "all-dates" if @all_dates

    @date.strftime("%d-%m-%Y")
  end

  def export_row(record, index)
    otp = @otp_status[record.mobile_no]
    lock = @locks[record.mobile_no]

    [
      index + 1,
      record.full_name,
      record.father_husband_name,
      # Masked here too: an exported sheet travels further than the screen.
      record.masked_mobile,
      record.masked_aadhaar,
      record.display_identifier_type == "aadhaar" ? "Aadhaar" : "Mobile",
      record.village_name,
      record.district_name,
      record.state_name,
      record.fco_name,
      record.ics_name,
      record.tracenet_id,
      record.display_login_count,
      export_time(record.display_first_login),
      export_time(record.display_last_login),
      otp&.status_label,
      export_time(otp&.created_at),
      otp&.attempts,
      lock&.locked? ? "Locked for #{lock.minutes_remaining} min" : "No",
      record.display_device,
      record.display_app_version,
      record.display_ip,
      record.display_place,
      record.display_latitude,
      record.display_longitude
    ]
  end

  def export_time(value)
    value.present? ? value.in_time_zone.strftime("%d-%m-%Y %I:%M %p") : nil
  end

  # The most recent OTP per mobile, in one statement. The OTP code itself is
  # never stored, so this reports what happened to it, not what it was.
  def latest_otp_by_mobile(mobiles)
    return {} if mobiles.blank?

    FarmerLoginOtpRequest
      .select("DISTINCT ON (mobile_no) *")
      .where(mobile_no: mobiles)
      .order(:mobile_no, created_at: :desc)
      .index_by(&:mobile_no)
  end

  # mobile_no is stored already normalised to ten digits, so a numeric search
  # compares it directly rather than stripping punctuation on every row -- a
  # function there would stop Postgres using the mobile_no index.
  def apply_search(scope)
    clauses = [
      "LOWER(COALESCE(farmer_app_logins.full_name, '')) LIKE :term",
      "LOWER(COALESCE(farmer_app_logins.father_husband_name, '')) LIKE :term",
      "LOWER(COALESCE(farmer_app_logins.village_name, '')) LIKE :term",
      "LOWER(COALESCE(farmer_app_logins.district_name, '')) LIKE :term",
      "LOWER(COALESCE(farmer_app_logins.ics_name, '')) LIKE :term",
      "LOWER(COALESCE(farmer_app_logins.tracenet_id, '')) LIKE :term"
    ]
    binds = { term: "%#{@search.downcase}%" }

    digits = @search.gsub(/\D/, "")
    if digits.present?
      clauses << "farmer_app_logins.mobile_no LIKE :digits"
      binds[:digits] = "#{digits}%"
    end

    scope.where(clauses.join(" OR "), **binds)
  end
end
