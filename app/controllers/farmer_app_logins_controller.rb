# Web list of farmers who have signed in from the Android app. Read-only.
class FarmerAppLoginsController < ApplicationController
  PER_PAGE = 50

  def index
    @search = params[:q].to_s.strip
    @page = [params[:page].to_i, 1].max

    scope = FarmerAppLogin.recent_first
    scope = apply_search(scope) if @search.present?

    @records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    counts = count_summary
    @total_count = counts[:total]
    @logged_in_today = counts[:today]
    @total_pages = [(@total_count / PER_PAGE.to_f).ceil, 1].max
  end

  private

  # Both counters come back in one trip. Run as two scopes they were two
  # sequential table reads for a page that already does one.
  def count_summary
    row = FarmerAppLogin.connection.select_one(
      FarmerAppLogin.sanitize_sql_array([
        "SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE last_logged_in_at >= :from AND last_logged_in_at < :to) AS today FROM farmer_app_logins",
        { from: Time.zone.now.beginning_of_day, to: Time.zone.now.end_of_day }
      ])
    ) || {}

    { total: row["total"].to_i, today: row["today"].to_i }
  end

  # mobile_no is stored already normalised to ten digits, so a numeric search
  # compares it directly rather than stripping punctuation on every row -- a
  # function there would stop Postgres using the mobile_no index.
  def apply_search(scope)
    clauses = [
      "LOWER(COALESCE(full_name, '')) LIKE :term",
      "LOWER(COALESCE(village_name, '')) LIKE :term",
      "LOWER(COALESCE(district_name, '')) LIKE :term",
      "LOWER(COALESCE(ics_name, '')) LIKE :term",
      "LOWER(COALESCE(tracenet_id, '')) LIKE :term"
    ]
    binds = { term: "%#{@search.downcase}%" }

    digits = @search.gsub(/\D/, "")
    if digits.present?
      clauses << "mobile_no LIKE :digits"
      binds[:digits] = "#{digits}%"
    end

    scope.where(clauses.join(" OR "), **binds)
  end
end
