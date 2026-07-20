class ContaminationControlRecord < ApplicationRecord
  include TabularImportExport
  include FarmerFarmLinkable

  CHANCE_OPTIONS = [
    "Machinery",
    "Water",
    "Air",
    "Neighbour",
    "Drift Control & Buffer Zone",
    "Storage",
    "Others"
  ].freeze
  EXPORT_COLUMNS = %i[
    chance_of_contamination source_details contamination_control_time prevention control remarks status
  ].freeze
  HEADER_LABELS = {
    chance_of_contamination: "Chances of contamination",
    source_details: "Source & Details",
    contamination_control_time: "Time of contamination control",
    prevention: "Contamination management - Prevention",
    control: "Contamination management - Control",
    remarks: "Remarks",
    status: "Status"
  }.freeze

  validates :status, inclusion: { in: %w[Active Inactive] }
end
