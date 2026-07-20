class FarmerFarmMapUploadsController < ApplicationController
  before_action :set_map_type, only: [:farm_map, :crop_map_session_wise]
  before_action :set_farm_map_upload, only: [:edit, :update, :destroy, :set_status]

  def farm_map
    render_upload_page
  end

  def crop_map_session_wise
    render_upload_page
  end

  def create
    @map_type = params.dig(:farmer_farm_map_upload, :map_type).to_s
    @map_title = FarmerFarmMapUpload.title_for(@map_type)
    @farm_map_upload = FarmerFarmMapUpload.new(farmer_farm_map_upload_params)

    if @farm_map_upload.save
      redirect_to path_for_map_type(@map_type), notice: "#{@map_title} photo uploaded successfully."
    else
      load_upload_page_state(@map_type)
      flash.now[:alert] = @farm_map_upload.errors.full_messages.to_sentence
      render :upload, status: :unprocessable_entity
    end
  rescue KeyError
    redirect_to farmer_farm_information_path, alert: "Invalid farm map page."
  end

  def edit
    @map_type = @farm_map_upload.map_type
    load_upload_page_state(@map_type)
    render :upload
  end

  def update
    @map_type = @farm_map_upload.map_type
    @map_title = FarmerFarmMapUpload.title_for(@map_type)

    if @farm_map_upload.update(farmer_farm_map_upload_params)
      redirect_to path_for_map_type(@map_type), notice: "#{@map_title} photo updated successfully."
    else
      load_upload_page_state(@map_type)
      flash.now[:alert] = @farm_map_upload.errors.full_messages.to_sentence
      render :upload, status: :unprocessable_entity
    end
  end

  def destroy
    map_type = @farm_map_upload.map_type
    @farm_map_upload.destroy
    redirect_to path_for_map_type(map_type), notice: "Farm map record deleted successfully."
  end

  def set_status
    map_type = @farm_map_upload.map_type
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @farm_map_upload.update(status: next_status)
    redirect_to path_for_map_type(map_type), notice: "Status changed to #{next_status}."
  end

  private

  def set_map_type
    @map_type = action_name == "farm_map" ? "farm_map" : "crop_map_session_wise"
  end

  def render_upload_page
    @farm_map_upload = FarmerFarmMapUpload.new(map_type: @map_type, status: "Active")
    load_upload_page_state(@map_type)
    render :upload
  end

  def load_upload_page_state(map_type)
    @map_title = FarmerFarmMapUpload.title_for(map_type)
    @map_uploads = FarmerFarmMapUpload.where(map_type: map_type).includes(:farmer_farm_information).with_attached_photo.order(created_at: :desc)
  end

  def set_farm_map_upload
    @farm_map_upload = FarmerFarmMapUpload.find(params[:id])
  end

  def path_for_map_type(map_type)
    map_type == "farm_map" ? farm_map_farmer_farm_information_path : crop_map_session_wise_farmer_farm_information_path
  end

  def farmer_farm_map_upload_params
    params.require(:farmer_farm_map_upload).permit(:farmer_farm_information_id, :map_type, :latitude, :longitude, :gps_accuracy, :photo)
  end
end
