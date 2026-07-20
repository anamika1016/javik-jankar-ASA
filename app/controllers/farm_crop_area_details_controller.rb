class FarmCropAreaDetailsController < ApplicationController
  before_action :set_farm_crop_area_detail, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = FarmCropAreaDetail.import(params[:file])
    redirect_to farm_crop_area_details_path, notice: import_notice(result, "farm crop area detail"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to farm_crop_area_details_path, alert: e.message
  end

  def export
    send_data FarmCropAreaDetail.to_xlsx(FarmCropAreaDetail.order(created_at: :desc)),
      filename: "farm_crop_area_details_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @farm_crop_area_detail = FarmCropAreaDetail.new(farm_crop_area_detail_params)

    if @farm_crop_area_detail.save
      redirect_to farm_crop_area_details_path, notice: "Farm crop area detail saved successfully."
    else
      load_index_state
      flash.now[:alert] = @farm_crop_area_detail.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @farm_crop_area_detail.update(farm_crop_area_detail_params)
      redirect_to farm_crop_area_details_path, notice: "Farm crop area detail updated successfully."
    else
      load_index_state
      flash.now[:alert] = @farm_crop_area_detail.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @farm_crop_area_detail.destroy
    redirect_to farm_crop_area_details_path, notice: "Farm crop area detail deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @farm_crop_area_detail.update(status: next_status)
    redirect_to farm_crop_area_details_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_farm_crop_area_detail
    @farm_crop_area_detail = FarmCropAreaDetail.find(params[:id])
  end

  def load_index_state
    @farm_crop_area_detail ||= FarmCropAreaDetail.new(status: "Active")
    @farm_crop_area_details = FarmCropAreaDetail.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def farm_crop_area_detail_params
    params.require(:farm_crop_area_detail).permit(
      :farmer_farm_information_id,
      :record_title,
      :crop_name,
      :area_hectares,
      :year_season_production,
      :perennial_age_plantation_time,
      :production_method,
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
