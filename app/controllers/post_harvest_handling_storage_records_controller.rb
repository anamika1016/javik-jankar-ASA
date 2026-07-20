class PostHarvestHandlingStorageRecordsController < ApplicationController
  before_action :set_post_harvest_handling_storage_record, only: [:edit, :update, :destroy, :set_status]

  def index
    load_index_state
  end

  def import
    result = PostHarvestHandlingStorageRecord.import(params[:file])
    redirect_to post_harvest_handling_storage_records_path, notice: import_notice(result, "post harvest handling storage"), alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to post_harvest_handling_storage_records_path, alert: e.message
  end

  def export
    send_data PostHarvestHandlingStorageRecord.to_xlsx(PostHarvestHandlingStorageRecord.order(created_at: :desc)),
      filename: "post_harvest_handling_storage_records_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  def create
    @post_harvest_handling_storage_record = PostHarvestHandlingStorageRecord.new(post_harvest_handling_storage_record_params)

    if @post_harvest_handling_storage_record.save
      redirect_to post_harvest_handling_storage_records_path, notice: "Post harvest handling storage record saved successfully."
    else
      load_index_state
      flash.now[:alert] = @post_harvest_handling_storage_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    load_index_state
    render :index
  end

  def update
    if @post_harvest_handling_storage_record.update(post_harvest_handling_storage_record_params)
      redirect_to post_harvest_handling_storage_records_path, notice: "Post harvest handling storage record updated successfully."
    else
      load_index_state
      flash.now[:alert] = @post_harvest_handling_storage_record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @post_harvest_handling_storage_record.destroy
    redirect_to post_harvest_handling_storage_records_path, notice: "Post harvest handling storage record deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @post_harvest_handling_storage_record.update(status: next_status)
    redirect_to post_harvest_handling_storage_records_path, notice: "Status changed to #{next_status}."
  end

  private

  def set_post_harvest_handling_storage_record
    @post_harvest_handling_storage_record = PostHarvestHandlingStorageRecord.find(params[:id])
  end

  def load_index_state
    @post_harvest_handling_storage_record ||= PostHarvestHandlingStorageRecord.new(status: "Active")
    @post_harvest_handling_storage_records = PostHarvestHandlingStorageRecord.includes(:farmer_farm_information).order(created_at: :desc).limit(200)
  end

  def post_harvest_handling_storage_record_params
    params.require(:post_harvest_handling_storage_record).permit(
      :farmer_farm_information_id,
      :crop_name,
      :post_harvest_treatment,
      :produce_name,
      :packing_material,
      :storage_area,
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
