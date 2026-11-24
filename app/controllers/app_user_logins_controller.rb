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
    visible_scope(scope)
  end

  # This page listed every sign-in to every login. An FCO office must only see
  # the people who belong to that office, the same rule the rest of the app
  # applies through AgreementVrpScope, and a Jeevika Jankar only their own.
  def visible_scope(scope)
    return scope if admin_login?
    return scope.where(record_type: "Vrp", record_id: current_app_user["id"]) if jeevika_jankar_login?

    office_keys = AgreementVrpScope.user_office_keys(current_app_user)
    # A login with no office of its own is left as it was rather than being
    # silently emptied; narrowing that case needs its own rule, not a guess.
    return scope if office_keys.blank?

    values = matching_office_values(office_keys)
    return scope.none if values.empty?

    scope.where(fcoc: values).or(scope.where(office_name: values))
  end

  # office_key folds "FCO-C Sausar", "FCO-Sausar" and "Sausar" onto one key, and
  # it does that in Ruby. Resolve the stored spellings that match once, then
  # filter on those exact values so the count and the page stay one SQL query -
  # the same approach the cluster label match uses.
  # visible_scope runs once for the list and once for the tiles, so without this
  # the distinct read below would scan the login table twice for every page.
  def matching_office_values(office_keys)
    @matching_office_values ||= AppUserLogin.distinct.pluck(:fcoc, :office_name)
      .flatten.compact_blank.uniq
      .select { |value| office_keys.include?(AgreementVrpScope.office_key(value)) }
  end

  def admin_login?
    current_app_user&.dig("user_type").to_s.strip.casecmp("admin").zero?
  end

  def jeevika_jankar_login?
    current_app_user&.dig("record_type").to_s == "Vrp" && current_app_user["id"].present?
  end

  # Both counters in one trip rather than two sequential reads. The tiles have
  # to count what the list is allowed to show, so they run over the same
  # visible scope - otherwise an FCO saw its own rows under the whole
  # organisation's totals. Kind and search stay out, as before: these are the
  # totals for the chosen dates, not for the current filter.
  def count_summary
    scope = AppUserLogin.all
    scope = scope.where(logged_in_at: @range) if @range
    person = "(record_type || ':' || record_id)"

    counts = visible_scope(scope).unscope(:order).pluck(
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(DISTINCT #{person})"),
      Arel.sql("COUNT(DISTINCT #{person}) FILTER (WHERE record_type = 'Vrp')"),
      Arel.sql("COUNT(DISTINCT #{person}) FILTER (WHERE record_type <> 'Vrp')")
    ).first || []

    {
      logins: counts[0].to_i,
      people: counts[1].to_i,
      jeevika_jankars: counts[2].to_i,
      staff: counts[3].to_i
    }
  end

  def export_row(record, index)
    [
      index + 1,
      record.logged_in_at&.in_time_zone&.strftime("%d-%m-%Y"),
      record.logged_in_at&.in_time_zone&.strftime("%I:%M %p"),
      record.name, record.username, record.user_kind, record.role,
      # Both columns are filled for either kind of user now; a Jeevika Jankar
      # carries their FCO in both, a staff user only in Office.
      record.office_label, record.fcoc,
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
