class PostHarvestHandlingStorageRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    crop_name post_harvest_treatment produce_name packing_material storage_area status
  ].freeze
  HEADER_LABELS = {
    crop_name: "Name of crop",
    post_harvest_treatment: "Post harvest treatment (Harvesting, Threshing, Winnowing, Cleaning)",
    produce_name: "Name of produce",
    packing_material: "Packing Material",
    storage_area: "Storage area",
    status: "Status"
  }.freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
end
