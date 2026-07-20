require "csv"
require "fileutils"
require "securerandom"

class AflsController < ApplicationController
  before_action :set_afl, only: [:destroy]

  PAGE_SIZE = 15
  REPORT_DIR = Rails.root.join("tmp", "afl_import_reports")

  def index
    @query = params[:q].to_s.strip
    @page = [params[:page].to_i, 1].max
    @page_size = PAGE_SIZE

    scoped_afls = Afl.search(@query)
    @total_afls = scoped_afls.count
    @total_pages = [(@total_afls.to_f / @page_size).ceil, 1].max
    @page = [@page, @total_pages].min

    @afls = scoped_afls
      .select(Afl::LIST_COLUMNS)
      .order(Arel.sql("farmer_name ASC NULLS LAST, id ASC"))
      .offset((@page - 1) * @page_size)
      .limit(@page_size)
  end

  def import
    result = Afl.import(params[:file])
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} target mapping records uploaded successfully out of #{total_rows} Excel rows."
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
    redirect_to afls_path(q: params[:q].presence, page: params[:page].presence), notice: "Target mapping record deleted successfully."
  end

  def bulk_destroy
    query = params[:q].to_s.strip
    scoped_afls = Afl.search(query)
    destroyed_count = scoped_afls.count

    scoped_afls.find_each(&:destroy)

    redirect_to afls_path(q: query.presence), notice: "#{destroyed_count} target mapping record(s) deleted successfully."
  end

  private

  def set_afl
    @afl = Afl.find(params[:id])
  end

  def write_import_report(skipped_rows)
    FileUtils.mkdir_p(REPORT_DIR)
    report_id = SecureRandom.hex(8)
    report_path = REPORT_DIR.join("#{report_id}.csv")

    CSV.open(report_path, "w") do |csv|
      csv << ["Row", "Reason", "Tracenet_No", "Longitude", "Lattitude", "Khasara_NO", "Farmer_Name", "Father_Name", "Village_ID", "Village_Name"]
      skipped_rows.each do |skipped_row|
        row = normalize_skipped_row(skipped_row)
        csv << [
          row[:row],
          row[:reason],
          row[:tracenet_no],
          row[:longitude],
          row[:lattitude],
          row[:khasara_no],
          row[:farmer_name],
          row[:father_name],
          row[:village_id],
          row[:village_name]
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
