class OnFarmInputRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    serial_no input_name preparation_date raw_material_details prepared_quantity status
  ].freeze
  HEADER_LABELS = {
    serial_no: "S No.",
    input_name: "Name of Input",
    preparation_date: "Date of input preparation",
    raw_material_details: "Details of raw material used",
    prepared_quantity: "Quantity of input prepared",
    status: "Status"
  }.freeze
  DATE_COLUMNS = %i[preparation_date].freeze
  DECIMAL_COLUMNS = %i[prepared_quantity].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :prepared_quantity, numericality: true, allow_blank: true
end
