class SeedPlantingMaterial < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    serial_no crop_name variety purchase_date supplier_name_address seed_type seed_treatment_details seed_quantity status
  ].freeze
  HEADER_LABELS = {
    serial_no: "S No.",
    crop_name: "Name of the crop",
    variety: "Variety",
    purchase_date: "Purchase date of seed",
    supplier_name_address: "Name of Supplier & Address",
    seed_type: "Type of seed",
    seed_treatment_details: "Seed Treatment (give details)",
    seed_quantity: "Quantity of seed (Kg /Ha)",
    status: "Status"
  }.freeze
  DATE_COLUMNS = %i[purchase_date].freeze
  DECIMAL_COLUMNS = %i[seed_quantity].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :seed_quantity, numericality: true, allow_blank: true
end
