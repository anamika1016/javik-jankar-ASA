class DispatchRecordsController < ApplicationController
  before_action :set_dispatch_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = DispatchRecord.import(params[:file])
    redirect_to dispatch_records_path, notice: import_notice(result, "dispatch"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to dispatch_records_path, alert: e.message
  end

  def export
    send_data DispatchRecord.to_xlsx(DispatchRecord.order(created_at: :desc)),
      filename: "dispatch_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @dispatch_record = DispatchRecord.new(dispatch_record_params)

    if @dispatch_record.save
      redirect_to dispatch_records_path, notice: "Dispatch record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @dispatch_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @dispatch_record.update(dispatch_record_params)
      redirect_to dispatch_records_path, notice: "Dispatch record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @dispatch_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @dispatch_record.destroy
    redirect_to dispatch_records_path, notice: "Dispatch record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @dispatch_record.update(status: next_status)
    redirect_to dispatch_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_dispatch_record
    @dispatch_record = DispatchRecord.find(params[:id])
  end

  def load_index_state
    @dispatch_record ||= DispatchRecord.new(status: "Active")
    @dispatch_records = DispatchRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def dispatch_record_params
    params.require(:dispatch_record).permit(
      :farmer_farm_information_id,
      :produce_name,
      :organic_status,
      :quantity_sold_to_ics_kg,
      :transport_date,
      :transport_quantity,
      :transport_mode,
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
