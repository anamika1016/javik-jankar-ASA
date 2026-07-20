class DiseasePestWeedManagementRecordsController < ApplicationController
  before_action :set_disease_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = DiseasePestWeedManagementRecord.import(params[:file])
    redirect_to disease_pest_weed_management_records_path, notice: import_notice(result, "disease pest weed management"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to disease_pest_weed_management_records_path, alert: e.message
  end

  def export
    send_data DiseasePestWeedManagementRecord.to_xlsx(DiseasePestWeedManagementRecord.order(created_at: :desc)),
      filename: "disease_pest_weed_management_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @disease_record = DiseasePestWeedManagementRecord.new(disease_record_params)

    if @disease_record.save
      redirect_to disease_pest_weed_management_records_path, notice: "Disease, insect, pest and weed management record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @disease_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @disease_record.update(disease_record_params)
      redirect_to disease_pest_weed_management_records_path, notice: "Disease, insect, pest and weed management record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @disease_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @disease_record.destroy
    redirect_to disease_pest_weed_management_records_path, notice: "Disease, insect, pest and weed management record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @disease_record.update(status: next_status)
    redirect_to disease_pest_weed_management_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_disease_record
    @disease_record = DiseasePestWeedManagementRecord.find(params[:id])
  end

  def load_index_state
    @disease_record ||= DiseasePestWeedManagementRecord.new(status: "Active")
    @disease_records = DiseasePestWeedManagementRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def disease_record_params
    params.require(:disease_pest_weed_management_record).permit(
      :farmer_farm_information_id,
      :farm_plot_no,
      :area,
      :crop_name,
      :pest_disease_weed_name,
      :treatment_name,
      :treatment_time,
      :input_source_brand,
      :application_rate,
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
