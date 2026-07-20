class OnFarmInputRecordsController < ApplicationController
  before_action :set_on_farm_input_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = OnFarmInputRecord.import(params[:file])
    redirect_to on_farm_input_records_path, notice: import_notice(result, "on farm input"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to on_farm_input_records_path, alert: e.message
  end

  def export
    send_data OnFarmInputRecord.to_xlsx(OnFarmInputRecord.order(created_at: :desc)),
      filename: "on_farm_input_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @on_farm_input_record = OnFarmInputRecord.new(on_farm_input_record_params)

    if @on_farm_input_record.save
      redirect_to on_farm_input_records_path, notice: "On farm input record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @on_farm_input_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @on_farm_input_record.update(on_farm_input_record_params)
      redirect_to on_farm_input_records_path, notice: "On farm input record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @on_farm_input_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @on_farm_input_record.destroy
    redirect_to on_farm_input_records_path, notice: "On farm input record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @on_farm_input_record.update(status: next_status)
    redirect_to on_farm_input_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_on_farm_input_record
    @on_farm_input_record = OnFarmInputRecord.find(params[:id])
  end

  def load_index_state
    @on_farm_input_record ||= OnFarmInputRecord.new(status: "Active")
    @on_farm_input_records = OnFarmInputRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def on_farm_input_record_params
    params.require(:on_farm_input_record).permit(:farmer_farm_information_id, :serial_no, :input_name, :preparation_date, :raw_material_details, :prepared_quantity, :status)
  end

  def import_notice(result, label)
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} #{label} record(s) uploaded successfully out of #{total_rows} Excel rows."
    notice += " #{result[:skipped].size} rows skipped." if result[:skipped].any?
    notice
  end
end
