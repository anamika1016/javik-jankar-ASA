class SeedPlantingMaterialsController < ApplicationController
  before_action :set_seed_planting_material, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = SeedPlantingMaterial.import(params[:file])
    redirect_to seed_planting_materials_path, notice: import_notice(result, "seed planting material"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to seed_planting_materials_path, alert: e.message
  end

  def export
    send_data SeedPlantingMaterial.to_xlsx(SeedPlantingMaterial.order(created_at: :desc)),
      filename: "seed_planting_materials_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @seed_planting_material = SeedPlantingMaterial.new(seed_planting_material_params)

    if @seed_planting_material.save
      redirect_to seed_planting_materials_path, notice: "Seed planting material saved successfully."
    else
      load_index_state
      flash.now[:alert] = @seed_planting_material.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @seed_planting_material.update(seed_planting_material_params)
      redirect_to seed_planting_materials_path, notice: "Seed planting material updated successfully."
    else
      load_index_state
      flash.now[:alert] = @seed_planting_material.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @seed_planting_material.destroy
    redirect_to seed_planting_materials_path, notice: "Seed planting material deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @seed_planting_material.update(status: next_status)
    redirect_to seed_planting_materials_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_seed_planting_material
    @seed_planting_material = SeedPlantingMaterial.find(params[:id])
  end

  def load_index_state
    @seed_planting_material ||= SeedPlantingMaterial.new(status: "Active")
    @seed_planting_materials = SeedPlantingMaterial.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def seed_planting_material_params
    params.require(:seed_planting_material).permit(:farmer_farm_information_id, :serial_no, :crop_name, :variety, :purchase_date, :supplier_name_address, :seed_type, :seed_treatment_details, :seed_quantity, :status)
  end

  def import_notice(result, label)
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} #{label} record(s) uploaded successfully out of #{total_rows} Excel rows."
    notice += " #{result[:skipped].size} rows skipped." if result[:skipped].any?
    notice
  end
end
