class SaleRecordsController < ApplicationController
  before_action :set_sale_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = SaleRecord.import(params[:file])
    redirect_to sale_records_path, notice: import_notice(result, "sale"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to sale_records_path, alert: e.message
  end

  def export
    send_data SaleRecord.to_xlsx(SaleRecord.order(created_at: :desc)),
      filename: "sale_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @sale_record = SaleRecord.new(sale_record_params)

    if @sale_record.save
      redirect_to sale_records_path, notice: "Sale record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @sale_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @sale_record.update(sale_record_params)
      redirect_to sale_records_path, notice: "Sale record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @sale_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @sale_record.destroy
    redirect_to sale_records_path, notice: "Sale record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @sale_record.update(status: next_status)
    redirect_to sale_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_sale_record
    @sale_record = SaleRecord.find(params[:id])
  end

  def load_index_state
    @sale_record ||= SaleRecord.new(status: "Active")
    @sale_records = SaleRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
    @organic_status_options = SaleRecord::ORGANIC_STATUS_OPTIONS
  end

  def sale_record_params
    params.require(:sale_record).permit(
      :farmer_farm_information_id,
      :produce_name,
      :organic_status,
      :total_output_for_sale_kg,
      :quantity_sold_to_ics_kg,
      :purchase_receipt_no,
      :balance_qty,
      :usage_consumption_other_issues,
      :remarks,
      :status
    )
  end

  def import_notice(result, label)
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} #{label} record(s) uploaded successfully out of #{total_rows} Excel rows."
    notice += " #{result[:skipped].size} rows skipped." if result[:skipped].any?
    notice
  end
end
