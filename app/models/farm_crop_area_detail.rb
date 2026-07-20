class FarmCropAreaDetail < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    record_title crop_name area_hectares year_season_production perennial_age_plantation_time production_method remarks status
  ].freeze
  HEADER_LABELS = {
    record_title: "Record Name",
    crop_name: "Name of the crop",
    area_hectares: "Area in Hectares",
    year_season_production: "Year and season of production",
    perennial_age_plantation_time: "Age and plantation time in case of perennial",
    production_method: "Method of production",
    remarks: "Remarks",
    status: "Status"
  }.freeze
  DECIMAL_COLUMNS = %i[area_hectares].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :area_hectares, numericality: true, allow_blank: true
end
