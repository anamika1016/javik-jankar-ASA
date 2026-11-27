require "csv"
require "fileutils"
require "securerandom"

class AflsController < ApplicationController
  before_action :set_afl, only: [:destroy]

  PAGE_SIZE = 15
  REPORT_DIR = Rails.root.join("tmp", "afl_import_reports")

  def index
    @query = params[:q].to_s.strip
    @column_filters = afl_column_filters
    @column_operators = afl_column_operators
    @dashboard_afl_filter_params = afl_dashboard_filter_params
    @page = [params[:page].to_i, 1].max
    @page_size = PAGE_SIZE

    scoped_afls = dashboard_filtered_afls(Afl.search(@query).column_search(@column_filters, @column_operators))
    @total_afls = scoped_afls.count
    @total_pages = [(@total_afls.to_f / @page_size).ceil, 1].max
    @page = [@page, @total_pages].min

    @afls = scoped_afls
      .select(Afl::LIST_COLUMNS)
      .order(Arel.sql("farmer_name ASC NULLS LAST, id ASC"))
      .offset((@page - 1) * @page_size)
      .limit(@page_size)

    respond_to do |format|
      format.html
      # The list is paginated, so exporting the rendered table would only ever
      # hold one page. Build the file from the whole filtered set instead.
      format.xlsx { send_afls_xlsx(scoped_afls) }
    end
  end

  def import
    result = Afl.import(params[:file])
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} AFL records uploaded successfully out of #{total_rows} Excel rows."
    notice += " #{result[:skipped].size} rows skipped." if result[:skipped].any?

    if result[:skipped].any?
      report_id = write_import_report(result[:skipped])
      redirect_to afls_path(report_id: report_id), notice: notice, alert: skipped_summary(result[:skipped])
    else
      redirect_to afls_path, notice: notice
    end
  rescue ArgumentError => e
    redirect_to afls_path, alert: e.message
  end

  def import_report
    report_path = REPORT_DIR.join("#{params[:id].to_s.gsub(/[^a-zA-Z0-9_-]/, "")}.csv")
    unless report_path.file?
      redirect_to afls_path, alert: "Target mapping import skipped report not found."
      return
    end

    send_file report_path, filename: "afl_skipped_rows_#{params[:id]}.csv", type: "text/csv"
  end

  def destroy
    @afl.destroy
    # Come back to the same search, page and filters the row was deleted from.
    return_params = afl_dashboard_filter_params
      .merge(q: params[:q].presence, page: params[:page].presence)
    return_params[:col] = afl_column_filters if afl_column_filters.any?
    return_params[:colop] = afl_column_operators if afl_column_operators.any?
    redirect_to afls_path(return_params), status: :see_other, notice: "Target mapping record deleted successfully."
  end

  def bulk_destroy
    query = params[:q].to_s.strip
    filters = afl_column_filters
    operators = afl_column_operators
    # The column filters have to narrow this exactly as they narrow the list.
    # Without them "delete all" would ignore the header boxes the rows on
    # screen were filtered by and delete far more than was being looked at.
    scoped_afls = Afl.search(query).column_search(filters, operators)
    destroyed_count = scoped_afls.count

    scoped_afls.find_each(&:destroy)

    redirect_to afls_path({ q: query.presence, col: filters.presence, colop: operators.presence }.compact),
      status: :see_other, notice: "#{destroyed_count} target mapping record(s) deleted successfully."
  end

  private

  # Everything this screen legitimately takes.
  #
  # Declaring the whole set in one place is what keeps the log quiet: a permit
  # call reports every parameter it was not told about, so the narrow
  # fcoc/ics/fco_id permit used to build link params was flagging q, page, col,
  # colop and the post-import report_id -- all expected here -- as unpermitted
  # on every request.
  def afl_permitted_params
    @afl_permitted_params ||= params.permit(
      :q, :page, :report_id, :fcoc, :ics, :format,
      fco_id: [], col: Afl::LIST_HEADERS.keys, colop: Afl::LIST_HEADERS.keys
    )
  end

  # Only the dashboard's own filters travel on this screen's links; the search,
  # page and report id are added by whoever needs them.
  def afl_dashboard_filter_params
    afl_permitted_params.slice(:fcoc, :ics, :fco_id).to_h.compact
  end

  # One search box per column heading. Only the columns the list shows are
  # accepted; anything else in the query string is ignored rather than reaching
  # the model.
  def afl_column_filters
    @afl_column_filters ||= permitted_column_params(:col)
      .transform_values { |value| value.to_s.strip }
      .reject { |_column, value| value.blank? }
  end

  # The comparison chosen in each header's dropdown. "Is empty" and "Is not
  # empty" are kept even though their box is blank -- those two ask about the
  # column's presence, so they are the filter.
  def afl_column_operators
    @afl_column_operators ||= permitted_column_params(:colop)
      .transform_values { |value| value.to_s.strip }
      .select { |column, operator| Afl::COLUMN_OPERATORS.key?(operator) && keep_operator?(column, operator) }
  end

  def keep_operator?(column, operator)
    Afl::VALUELESS_COLUMN_OPERATORS.include?(operator) || afl_column_filters.key?(column)
  end

  def permitted_column_params(key)
    afl_permitted_params[key].to_h
  end

  AFL_EXPORT_COLUMNS = {
    "ID" => :id,
    "FCO ID" => :fco_id,
    "FCO" => :fco,
    "FPO ID" => :fpo_id,
    "FPO Name" => :fpo_name,
    "ICS ID" => :ics_id,
    "ICS Name" => :ics_name,
    "Village ID" => :village_id,
    "Village Name" => :village_name,
    "Farm ID" => :farm_id,
    "Farmer Name" => :farmer_name,
    "Father Name" => :father_name,
    "Tracenet No" => :tracenet_no,
    "Total Farm Area" => :total_farm_area,
    "Purchase Quantity Amount" => :purchase_quantity_amount,
    "Estimate Quantity" => :estimate_quantity,
    "Purchase Quantity" => :purchase_quantity,
    "Purchase Date" => :purchase_date,
    "Mobile No" => :mobile_no,
    "Purchase Product" => :purchase_product,
    "Status" => :status
  }.freeze

  def send_afls_xlsx(scope)
    columns = AFL_EXPORT_COLUMNS.values
    date_index = columns.index(:purchase_date)

    # pluck keeps this to raw values; instantiating every row would be heavy on
    # a list this size.
    rows = scope
      .order(Arel.sql("farmer_name ASC NULLS LAST, id ASC"))
      .pluck(*columns)
      .each { |row| row[date_index] = row[date_index]&.strftime("%d-%m-%Y") }

    send_xlsx(
      headers: AFL_EXPORT_COLUMNS.keys,
      rows: rows,
      filename: "afl-upload-#{Time.current.strftime('%Y%m%d%H%M')}.xlsx",
      sheet_name: "AFL Upload"
    )
  end

  def set_afl
    @afl = Afl.find(params[:id])
  end

  def dashboard_filtered_afls(scope)
    fco_ids = Array(params[:fco_id]).flatten.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    fcoc = params[:fcoc].to_s.strip
    ics = params[:ics].to_s.strip

    scope = scope.where("LOWER(BTRIM(COALESCE(fco_id, ''))) IN (:fco_ids)", fco_ids: fco_ids.map(&:downcase)) if fco_ids.any?
    if fcoc.present?
      normalized_fcoc = fcoc.downcase
      short_fcoc = normalized_fcoc.sub(/\Afco\s*-\s*c\s+/, "").strip
      scope = scope.where(
        "LOWER(BTRIM(COALESCE(fco, ''))) IN (:fcocs) OR LOWER(BTRIM(COALESCE(fco_id, ''))) IN (:fcocs)",
        fcocs: [normalized_fcoc, short_fcoc].uniq
      )
    end
    if ics.present?
      normalized_ics = ics.downcase
      scope = scope.where(
        "LOWER(BTRIM(COALESCE(ics_name, ''))) = :ics OR LOWER(BTRIM(COALESCE(ics_id, ''))) = :ics",
        ics: normalized_ics
      )
    end
    scope
  end

  def write_import_report(skipped_rows)
    FileUtils.mkdir_p(REPORT_DIR)
    report_id = SecureRandom.hex(8)
    report_path = REPORT_DIR.join("#{report_id}.csv")

    CSV.open(report_path, "w") do |csv|
      csv << ["Row", "Reason", "ID", "Tracenet_No", "Longitude", "Lattitude", "Khasara_NO", "Farmer_Name", "Father_Name", "Village_ID", "Village_Name", "Farm_ID"]
      skipped_rows.each do |skipped_row|
        row = normalize_skipped_row(skipped_row)
        csv << [
          row[:row],
          row[:reason],
          row[:id],
          row[:tracenet_no],
          row[:longitude],
          row[:lattitude],
          row[:khasara_no],
          row[:farmer_name],
          row[:father_name],
          row[:village_id],
          row[:village_name],
          row[:farm_id]
        ]
      end
    end

    report_id
  end

  def skipped_summary(skipped_rows)
    reason_counts = skipped_rows
      .map { |skipped_row| normalize_skipped_row(skipped_row)[:reason] }
      .tally
      .map { |reason, count| "#{count} #{reason}" }
      .join(" | ")

    "Skipped reason summary: #{reason_counts}"
  end

  def normalize_skipped_row(skipped_row)
    return skipped_row.symbolize_keys if skipped_row.respond_to?(:symbolize_keys)

    message = skipped_row.to_s
    {
      row: message[/\ARow (\d+):/, 1],
      reason: message.sub(/\ARow \d+:\s*/, "")
    }
  end
end
