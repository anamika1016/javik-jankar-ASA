class SaleRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  ORGANIC_STATUS_OPTIONS = [
    "Organic",
    "In conversion"
  ].freeze

  EXPORT_COLUMNS = %i[
    produce_name organic_status total_output_for_sale_kg quantity_sold_to_ics_kg purchase_receipt_no balance_qty usage_consumption_other_issues remarks status
  ].freeze
  HEADER_LABELS = {
    produce_name: "Name of the produce",
    organic_status: "Organic status (Organic in conversion)",
    total_output_for_sale_kg: "Total output for sale (Kg)",
    quantity_sold_to_ics_kg: "Quantity sold to ICS",
    purchase_receipt_no: "Purchase Receipt no. issued by ICS",
    balance_qty: "Balance Qty",
    usage_consumption_other_issues: "Usage Consumption Other issues",
    remarks: "Remarks",
    status: "Status"
  }.freeze
  DECIMAL_COLUMNS = %i[total_output_for_sale_kg quantity_sold_to_ics_kg balance_qty].freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :organic_status, inclusion: { in: ORGANIC_STATUS_OPTIONS }, allow_blank: true
  validates :total_output_for_sale_kg, :quantity_sold_to_ics_kg, :balance_qty, numericality: true, allow_blank: true
end
