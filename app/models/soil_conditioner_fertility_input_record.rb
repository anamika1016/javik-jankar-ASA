class SoilConditionerFertilityInputRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    serial_no farm_plot_no crop_name input_name input_source_brand application_time application_rate status
  ].freeze
  HEADER_LABELS = {
    serial_no: "S No.",
    farm_plot_no: "Name of farm /plot no",
    crop_name: "Name of the crop",
    input_name: "Name of the inputs",
    input_source_brand: "Source of input /brand",
    application_time: "Application Time",
    application_rate: "Application Rate",
    status: "Status"
  }.freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
end
