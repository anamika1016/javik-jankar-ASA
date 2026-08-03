class FarmerFarmInformationController < ApplicationController
  FARM_INFORMATION_AFL_FCO_ID = "1009".freeze

  before_action :set_farmer_farm_information, only: [:edit, :update, :destroy, :set_status]
  before_action :set_ics_exit_declaration, only: [
    :show_ics_exit_declaration,
    :edit_ics_exit_declaration,
    :update_ics_exit_declaration,
    :destroy_ics_exit_declaration
  ]

  def index
    load_index_state
  end

  def list
    @query = params[:q].to_s.strip
    @farmer_farm_information_records = FarmerFarmInformation.search(@query).order(created_at: :desc).limit(500)
  end

  def ics_exit_declaration
    @ics_exit_declaration = IcsExitDeclaration.new(declaration_date: Date.current, status: "Active")
    load_ics_exit_declaration_state
  end

  def create_ics_exit_declaration
    @ics_exit_declaration = IcsExitDeclaration.new(ics_exit_declaration_params)

    if @ics_exit_declaration.save
      redirect_to ics_exit_declaration_record_path(@ics_exit_declaration), notice: "ICS exit declaration saved successfully."
    else
      load_ics_exit_declaration_state
      flash.now[:alert] = @ics_exit_declaration.errors.full_messages.to_sentence
      render :ics_exit_declaration, status: :unprocessable_entity
    end
  end

  def show_ics_exit_declaration
  end

  def edit_ics_exit_declaration
    load_ics_exit_declaration_state
    render :ics_exit_declaration
  end

  def update_ics_exit_declaration
    if @ics_exit_declaration.update(ics_exit_declaration_params)
      redirect_to ics_exit_declaration_record_path(@ics_exit_declaration), notice: "ICS exit declaration updated successfully."
    else
      load_ics_exit_declaration_state
      flash.now[:alert] = @ics_exit_declaration.errors.full_messages.to_sentence
      render :ics_exit_declaration, status: :unprocessable_entity
    end
  end

  def destroy_ics_exit_declaration
    @ics_exit_declaration.destroy
    redirect_to ics_exit_declaration_farmer_farm_information_path, notice: "ICS exit declaration deleted successfully."
  end

  def edit
    load_index_state
    render :index
  end

  def create
    @farmer_farm_information = FarmerFarmInformation.new(farmer_farm_information_params)

    if @farmer_farm_information.save
      redirect_to farmer_farm_information_path, notice: "Farmer farm information saved successfully."
    else
      load_index_state
      flash.now[:alert] = @farmer_farm_information.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @farmer_farm_information.update(farmer_farm_information_params)
      redirect_to farmer_farm_information_path, notice: "Farmer farm information updated successfully."
    else
      load_index_state
      flash.now[:alert] = @farmer_farm_information.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @farmer_farm_information.destroy
    redirect_to list_farmer_farm_information_path, notice: "Farmer farm information deleted successfully."
  end

  def set_status
    next_status = params[:status].presence_in(["Active", "Inactive"]) || "Active"
    @farmer_farm_information.update(status: next_status)
    redirect_to list_farmer_farm_information_path, notice: "Status changed to #{next_status}."
  end

  def import
    result = FarmerFarmInformation.import(params[:file])
    total_rows = result[:imported] + result[:skipped].size
    notice = "#{result[:imported]} farmer farm information records uploaded successfully out of #{total_rows} Excel rows."
    notice += " #{result[:skipped].size} rows skipped." if result[:skipped].any?

    redirect_to list_farmer_farm_information_path, notice: notice, alert: result[:skipped].first(5).join(" | ").presence
  rescue ArgumentError => e
    redirect_to farmer_farm_information_path, alert: e.message
  end

  def export
    records = FarmerFarmInformation.search(params[:q]).order(created_at: :desc)

    send_data FarmerFarmInformation.to_xlsx(records),
      filename: "farmer_farm_information_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx",
      type: XlsxExporter::MIME_TYPE
  end

  private

  def set_farmer_farm_information
    @farmer_farm_information = FarmerFarmInformation.find(params[:id])
  end

  def set_ics_exit_declaration
    @ics_exit_declaration = IcsExitDeclaration.find(params[:id])
  end

  def load_index_state
    @query = params[:q].to_s.strip
    @edit_farmer_farm_information = FarmerFarmInformation.find_by(id: params[:edit_id]) if params[:edit_id].present?
    @farmer_farm_information ||= @edit_farmer_farm_information || FarmerFarmInformation.new
    @afl_farmer_options = bhabhra_afls.map do |afl|
      label = [afl.farmer_name, afl.tracenet_no.presence].compact.join(" — ")
      [label, afl.farmer_name, {
        data: {
          afl_farm_id: afl.id,
          afl_ics_name: afl.ics_name,
          afl_tracenet_no: afl.tracenet_no,
          afl_crop_year: afl.fy,
          afl_aadhar_number: afl.aadhar
        }
      }]
    end
    @afl_ics_name_options = afl_distinct_options(:ics_name, @farmer_farm_information.ics_name)
    @afl_tracenet_no_options = afl_distinct_options(:tracenet_no, @farmer_farm_information.tracenet_no)
    @production_technique_options = FarmerFarmInformation::PRODUCTION_TECHNIQUES
    @certification_status_options = FarmerFarmInformation::CERTIFICATION_STATUSES
  end

  def afl_distinct_options(column, current_value)
    values = bhabhra_afls
      .map { |afl| afl.public_send(column) }
      .map { |value| value.to_s.strip }
      .reject(&:blank?)
      .uniq
      .sort
    values.unshift(current_value.to_s) if current_value.present? && !values.include?(current_value.to_s)
    values
  end

  def bhabhra_afls
    @bhabhra_afls ||= Afl.where(fco_id: FARM_INFORMATION_AFL_FCO_ID)
      .where.not(farmer_name: [nil, ""])
      .order(:farmer_name, :tracenet_no)
      .limit(2_000)
      .to_a
  end

  def load_ics_exit_declaration_state
    @query = params[:q].to_s.strip
    @farmer_options = FarmerFarmInformation.order(:farm_id, :farmer_name).limit(1_000)
    @farmer_detail_map = @farmer_options.each_with_object({}) do |farmer, details|
      details[farmer.id] = {
        farm_id: farmer.farm_id.to_s,
        farmer_name: farmer.farmer_name.to_s,
        id_number: farmer.farm_id.to_s,
        farmer_address: farmer.farmer_address.to_s,
        farmer_contact_no: farmer.farmer_contact_no.to_s,
        farmer_village: farmer.farmer_village.to_s,
        tracenet_no: farmer.tracenet_no.to_s,
        ics_name: farmer.ics_name.to_s,
        grower_group_name: farmer.ics_name.to_s,
        certification_status: farmer.certification_status.to_s
      }
    end
    @ics_exit_declarations = IcsExitDeclaration.search(@query).order(created_at: :desc).limit(500)
  end

  def farmer_farm_information_params
    params.require(:farmer_farm_information).permit(
      :farm_id,
      :ics_name,
      :current_crop_year,
      :season,
      :farmer_name,
      :tracenet_no,
      :father_mother_name,
      :aadhar_number,
      :farmer_address,
      :farmer_pincode,
      :farmer_contact_no,
      :farmer_state,
      :farmer_district,
      :farmer_block,
      :farmer_gram,
      :farmer_village,
      :farm_name,
      :farm_address,
      :farm_state,
      :farm_district,
      :farm_block,
      :farm_gram,
      :farm_village,
      :latitude,
      :longitude,
      :khasra_no,
      :land_details,
      :total_land,
      :no_of_farms_plots,
      :total_land_offered_for_organic_certification,
      :organic_production_started_year,
      :date_of_joining_ics,
      :present_production_technique,
      :crops_under_organic_production_area,
      :other_crops_name_area,
      :certification_status,
      :name_of_accredited_certification_body,
      :status
    )
  end

  def ics_exit_declaration_params
    params.require(:ics_exit_declaration).permit(
      :farmer_farm_information_id,
      :farm_id,
      :farmer_name,
      :id_number,
      :farmer_address,
      :farmer_contact_no,
      :farmer_village,
      :tracenet_no,
      :ics_name,
      :grower_group_name,
      :exit_reason,
      :certification_status,
      :new_certification_body,
      :declaration_date,
      :signature_of_farmer,
      :status
    )
  end
end
