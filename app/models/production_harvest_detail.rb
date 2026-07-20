class ProductionHarvestDetail < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    farm_plot_name year_season crop_produce_name area_hectares estimated_production_mt harvest_time actual_production_mt status
  ].freeze
  HEADER_LABELS = {
    farm_plot_name: "Name of farm /plot",
    year_season: "Year & season",
    crop_produce_name: "Name of the crop/produce",
    area_hectares: "Area (Ha)",
    estimated_production_mt: "Estimated production (MT)",
    harvest_time: "Time of harvest",
    actual_production_mt: "Actual production (MT)",
    status: "Status"
  }.freeze
  DECIMAL_COLUMNS = %i[area_hectares estimated_production_mt actual_production_mt].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :area_hectares, :estimated_production_mt, :actual_production_mt, numericality: true, allow_blank: true
end
