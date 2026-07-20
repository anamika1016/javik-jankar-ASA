module FarmerFarmLinkable
  extend ActiveSupport::Concern

  included do
    belongs_to :farmer_farm_information, optional: true
    before_validation :link_farmer_farm_information_from_plot_reference
    before_validation :sync_plot_reference_from_farmer_farm_information
  end

  def linked_farm_id
    farmer_farm_information&.farm_id
  end

  def linked_farmer_name
    farmer_farm_information&.farmer_name
  end

  def linked_ics_name
    farmer_farm_information&.ics_name
  end

  private

  def link_farmer_farm_information_from_plot_reference
    return if farmer_farm_information_id.present?

    plot_reference = farmer_farm_plot_reference
    return if plot_reference.blank?

    self.farmer_farm_information = FarmerFarmInformation.find_by(farm_id: plot_reference.to_s.strip)
  end

  def sync_plot_reference_from_farmer_farm_information
    return unless farmer_farm_information

    farm_id = farmer_farm_information.farm_id
    return if farm_id.blank?

    self.farm_plot_no = farm_id if respond_to?(:farm_plot_no=) && farm_plot_no.blank?
    self.farm_plot_name = farm_id if respond_to?(:farm_plot_name=) && farm_plot_name.blank?
  end

  def farmer_farm_plot_reference
    return farm_plot_no if respond_to?(:farm_plot_no) && farm_plot_no.present?
    return farm_plot_name if respond_to?(:farm_plot_name) && farm_plot_name.present?
  end
end
