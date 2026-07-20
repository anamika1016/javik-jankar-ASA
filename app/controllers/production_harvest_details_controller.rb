class ProductionHarvestDetailsController < ApplicationController
  before_action :set_production_harvest_detail, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = ProductionHarvestDetail.import(params[:file])
    redirect_to production_harvest_details_path, notice: import_notice(result, "production harvest detail"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to production_harvest_details_path, alert: e.message
  end

  def export
    send_data ProductionHarvestDetail.to_xlsx(ProductionHarvestDetail.order(created_at: :desc)),
      filename: "production_harvest_details_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @production_harvest_detail = ProductionHarvestDetail.new(production_harvest_detail_params)

    if @production_harvest_detail.save
      redirect_to production_harvest_details_path, notice: "Production harvest detail saved successfully."
    else
      load_index_state
      flash.now[:alert] = @production_harvest_detail.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @production_harvest_detail.update(production_harvest_detail_params)
      redirect_to production_harvest_details_path, notice: "Production harvest detail updated successfully."
    else
      load_index_state
      flash.now[:alert] = @production_harvest_detail.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @production_harvest_detail.destroy
    redirect_to production_harvest_details_path, notice: "Production harvest detail deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @production_harvest_detail.update(status: next_status)
    redirect_to production_harvest_details_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_production_harvest_detail
    @production_harvest_detail = ProductionHarvestDetail.find(params[:id])
  end

  def load_index_state
    @production_harvest_detail ||= ProductionHarvestDetail.new(status: "Active")
    @production_harvest_details = ProductionHarvestDetail.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def production_harvest_detail_params
    params.require(:production_harvest_detail).permit(
      :farmer_farm_information_id,
      :farm_plot_name,
      :year_season,
      :crop_produce_name,
      :area_hectares,
      :estimated_production_mt,
      :harvest_time,
      :actual_production_mt,
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
