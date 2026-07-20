class DiseasePestWeedManagementRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    farm_plot_no area crop_name pest_disease_weed_name treatment_name treatment_time input_source_brand application_rate status
  ].freeze
  HEADER_LABELS = {
    farm_plot_no: "Name of farm /plot no.",
    area: "Area",
    crop_name: "Name of the crop",
    pest_disease_weed_name: "Name of pest, disease and weed",
    treatment_name: "Treatment used for control - Name",
    treatment_time: "Treatment used for control - Time",
    input_source_brand: "Source / brand of input",
    application_rate: "Rate of application",
    status: "Status"
  }.freeze
  DECIMAL_COLUMNS = %i[area].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :area, numericality: true, allow_blank: true
end
