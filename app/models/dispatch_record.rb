class DispatchRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  EXPORT_COLUMNS = %i[
    produce_name organic_status quantity_sold_to_ics_kg transport_date transport_quantity transport_mode remarks status
  ].freeze
  HEADER_LABELS = {
    produce_name: "Name of the produce",
    organic_status: "Organic status",
    quantity_sold_to_ics_kg: "Quantity sold to ICS(Kg)",
    transport_date: "Details of transport - Date",
    transport_quantity: "Details of transport - Quantity",
    transport_mode: "Details of transport - Mode",
    remarks: "Remarks",
    status: "Status"
  }.freeze
  DATE_COLUMNS = %i[transport_date].freeze
  DECIMAL_COLUMNS = %i[quantity_sold_to_ics_kg transport_quantity].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :quantity_sold_to_ics_kg, :transport_quantity, numericality: true, allow_blank: true
end
