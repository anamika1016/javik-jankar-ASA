class SoilConditionerFertilityInputRecordsController < ApplicationController
  before_action :set_soil_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = SoilConditionerFertilityInputRecord.import(params[:file])
    redirect_to soil_conditioner_fertility_input_records_path, notice: import_notice(result, "soil conditioner"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to soil_conditioner_fertility_input_records_path, alert: e.message
  end

  def export
    send_data SoilConditionerFertilityInputRecord.to_xlsx(SoilConditionerFertilityInputRecord.order(created_at: :desc)),
      filename: "soil_conditioner_fertility_input_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @soil_record = SoilConditionerFertilityInputRecord.new(soil_record_params)

    if @soil_record.save
      redirect_to soil_conditioner_fertility_input_records_path, notice: "Soil conditioner record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @soil_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @soil_record.update(soil_record_params)
      redirect_to soil_conditioner_fertility_input_records_path, notice: "Soil conditioner record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @soil_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @soil_record.destroy
    redirect_to soil_conditioner_fertility_input_records_path, notice: "Soil conditioner record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @soil_record.update(status: next_status)
    redirect_to soil_conditioner_fertility_input_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_soil_record
    @soil_record = SoilConditionerFertilityInputRecord.find(params[:id])
  end

  def load_index_state
    @soil_record ||= SoilConditionerFertilityInputRecord.new(status: "Active")
    @soil_records = SoilConditionerFertilityInputRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def soil_record_params
    params.require(:soil_conditioner_fertility_input_record).permit(:farmer_farm_information_id, :serial_no, :farm_plot_no, :crop_name, :input_name, :input_source_brand, :application_time, :application_rate, :status)
  end

  def import_notice(result, label)
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} #{label} record(s) uploaded successfully out of #{total_rows} Excel rows."
    notice += " #{result[:skipped].size} rows skipped." if result[:skipped].any?
    notice
  end
end
