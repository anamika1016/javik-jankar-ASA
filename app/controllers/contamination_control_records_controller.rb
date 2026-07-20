class ContaminationControlRecordsController < ApplicationController
  before_action :set_contamination_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = ContaminationControlRecord.import(params[:file])
    redirect_to contamination_control_records_path, notice: import_notice(result, "contamination control"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to contamination_control_records_path, alert: e.message
  end

  def export
    send_data ContaminationControlRecord.to_xlsx(ContaminationControlRecord.order(created_at: :desc)),
      filename: "contamination_control_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @contamination_record = ContaminationControlRecord.new(contamination_record_params)

    if @contamination_record.save
      redirect_to contamination_control_records_path, notice: "Contamination control record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @contamination_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @contamination_record.update(contamination_record_params)
      redirect_to contamination_control_records_path, notice: "Contamination control record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @contamination_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @contamination_record.destroy
    redirect_to contamination_control_records_path, notice: "Contamination control record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @contamination_record.update(status: next_status)
    redirect_to contamination_control_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_contamination_record
    @contamination_record = ContaminationControlRecord.find(params[:id])
  end

  def load_index_state
    @contamination_record ||= ContaminationControlRecord.new(status: "Active")
    @contamination_records = ContaminationControlRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
    @chance_options = ContaminationControlRecord::CHANCE_OPTIONS
  end

  def contamination_record_params
    params.require(:contamination_control_record).permit(
      :farmer_farm_information_id,
      :chance_of_contamination,
      :source_details,
      :contamination_control_time,
      :prevention,
      :control,
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
