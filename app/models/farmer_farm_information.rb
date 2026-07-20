require "bigdecimal"
require "csv"
require "date"
require "rexml/document"
require "zip"

class FarmerFarmInformation < ApplicationRecord
  self.table_name = "farmer_farm_information"

  IMPORT_COLUMNS = %i[
    farm_id ics_name current_crop_year season farmer_name tracenet_no father_mother_name aadhar_number
    farmer_address farmer_pincode farmer_contact_no farmer_state farmer_district farmer_block farmer_gram farmer_village
    farm_name farm_address farm_state farm_district farm_block farm_gram farm_village latitude longitude khasra_no
    land_details total_land no_of_farms_plots total_land_offered_for_organic_certification
    organic_production_started_year date_of_joining_ics present_production_technique crops_under_organic_production_area
    other_crops_name_area certification_status name_of_accredited_certification_body
    status
  ].freeze

  EXPORT_COLUMNS = IMPORT_COLUMNS.freeze

  HEADER_LABELS = {
    farm_id: "Farm ID",
    ics_name: "ICS Name",
    current_crop_year: "Current Crop Year",
    season: "Season",
    farmer_name: "Farmer Name",
    tracenet_no: "Tracenet No",
    father_mother_name: "Father/Mother Name",
    aadhar_number: "Aadhar Number",
    farmer_address: "Farmer Address",
    farmer_pincode: "Farmer Pincode",
    farmer_contact_no: "Farmer Contact No",
    farmer_state: "Farmer State",
    farmer_district: "Farmer District",
    farmer_block: "Farmer Block",
    farmer_gram: "Farmer Gram",
    farmer_village: "Farmer Village",
    farm_name: "Farm Name",
    farm_address: "Farm Address",
    farm_state: "Farm State",
    farm_district: "Farm District",
    farm_block: "Farm Block",
    farm_gram: "Farm Gram",
    farm_village: "Farm Village",
    latitude: "Latitude",
    longitude: "Longitude",
    khasra_no: "Khasra No",
    land_details: "Land Details",
    total_land: "Total Land (Acre)",
    no_of_farms_plots: "No. of Farms/Plots",
    total_land_offered_for_organic_certification: "Total Land Offered for Organic Certification (Acre)",
    organic_production_started_year: "Year in which Organic Production was Started by the Farmer",
    date_of_joining_ics: "Date of Joining of Farmer in the ICS",
    present_production_technique: "Present Production Technique",
    crops_under_organic_production_area: "Crops under Organic Production and their Area",
    other_crops_name_area: "Other crops (name and area)",
    certification_status: "Certification Status",
    name_of_accredited_certification_body: "Name of the accredited Certification Body",
    status: "Status"
  }.freeze

  NORMALIZE_HEADER = ->(value) { value.to_s.downcase.gsub(/[^a-z0-9]+/, "") }

  HEADER_ALIASES = HEADER_LABELS.each_with_object({}) do |(column, label), aliases|
    aliases[NORMALIZE_HEADER.call(label)] = column
    aliases[NORMALIZE_HEADER.call(column)] = column
  end.merge(
    NORMALIZE_HEADER.call("Farmer_FARM _Information") => :farm_id,
    NORMALIZE_HEADER.call("no_of_farms /PLOT") => :no_of_farms_plots,
    NORMALIZE_HEADER.call("No. of Farms/Plots") => :no_of_farms_plots,
    NORMALIZE_HEADER.call("Total Land Offered for Organic Certification") => :total_land_offered_for_organic_certification,
    NORMALIZE_HEADER.call("Total Land") => :total_land
  ).freeze

  DECIMAL_COLUMNS = %i[latitude longitude total_land total_land_offered_for_organic_certification].freeze
  INTEGER_COLUMNS = %i[no_of_farms_plots].freeze
  DATE_COLUMNS = %i[date_of_joining_ics].freeze

  PRODUCTION_TECHNIQUES = [
    "Fully Chemical",
    "Part Organic-Split",
    "Part Organic-Parallel",
    "Fully Organic",
    "Others"
  ].freeze

  CERTIFICATION_STATUSES = [
    "In conversion",
    "Organic"
  ].freeze

  before_validation :default_status

  has_many :farmer_farm_map_uploads, dependent: :nullify
  has_many :farm_crop_area_details, dependent: :nullify
  has_many :seed_planting_materials, dependent: :nullify
  has_many :soil_conditioner_fertility_input_records, dependent: :nullify
  has_many :on_farm_input_records, dependent: :nullify
  has_many :disease_pest_weed_management_records, dependent: :nullify
  has_many :contamination_control_records, dependent: :nullify
  has_many :production_harvest_details, dependent: :nullify
  has_many :post_harvest_handling_storage_records, dependent: :nullify
  has_many :sale_records, dependent: :nullify
  has_many :dispatch_records, dependent: :nullify

  SEARCHABLE_COLUMNS = %i[
    farm_id ics_name current_crop_year season farmer_name tracenet_no father_mother_name
    aadhar_number farmer_contact_no farmer_state farmer_district farmer_block farmer_gram farmer_village
    farm_name farm_state farm_district farm_block farm_gram farm_village khasra_no
    organic_production_started_year present_production_technique other_crops_name_area certification_status
    name_of_accredited_certification_body status
  ].freeze

  validates :farm_id, :farmer_name, presence: true
  validates :status, inclusion: { in: %w[Active Inactive] }
  validates :certification_status, inclusion: { in: CERTIFICATION_STATUSES }, allow_blank: true
  validates :total_land,
            :total_land_offered_for_organic_certification,
            :latitude,
            :longitude,
            numericality: true,
            allow_blank: true
  validates :no_of_farms_plots, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_blank: true

  def self.search(query)
    query = query.to_s.strip
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query)}%"
    where(
      SEARCHABLE_COLUMNS.map { |column| "#{connection.quote_column_name(column)}::text ILIKE :query" }.join(" OR "),
      query: pattern
    )
  end

  def self.import(file)
    raise ArgumentError, "Please choose an Excel or CSV file." unless file.present?

    rows = rows_from_upload(file)
    headers = rows.shift
    raise ArgumentError, "Uploaded file is blank." if headers.blank?

    import_rows(rows, headers)
  end

  def self.import_rows(rows, headers)
    attributes_by_index = headers.map { |header| column_for_header(header) }
    imported = 0
    skipped = []

    rows.each_with_index do |row, index|
      attrs = attributes_from_row(row, attributes_by_index)
      next if attrs.values.all?(&:blank?)

      record = new(attrs)
      if record.save
        imported += 1
      else
        skipped << "Row #{index + 2}: #{record.errors.full_messages.to_sentence}"
      end
    end

    { imported: imported, skipped: skipped }
  end

  def self.to_csv(records = all)
    CSV.generate(headers: true) do |csv|
      csv << EXPORT_COLUMNS.map { |column| HEADER_LABELS.fetch(column) }
      records.each do |record|
        csv << EXPORT_COLUMNS.map { |column| record.public_send(column) }
      end
    end
  end

  def self.to_xlsx(records = all)
    XlsxExporter.generate(
      headers: EXPORT_COLUMNS.map { |column| HEADER_LABELS.fetch(column) },
      rows: records.map { |record| EXPORT_COLUMNS.map { |column| record.public_send(column) } },
      sheet_name: "Farmer Farm Information"
    )
  end

  def self.rows_from_upload(file)
    extension = File.extname(file.original_filename.to_s).downcase

    case extension
    when ".csv"
      CSV.read(file.path, headers: false)
    when ".xlsx"
      rows_from_xlsx(file.path)
    else
      raise ArgumentError, "Only .xlsx and .csv files are supported."
    end
  end

  def self.rows_from_xlsx(path)
    Zip::File.open(path) do |zip|
      shared_strings = xlsx_shared_strings(zip)
      sheet_entry = zip.find_entry("xl/worksheets/sheet1.xml")
      raise ArgumentError, "Could not find first sheet in the Excel file." unless sheet_entry

      sheet = REXML::Document.new(sheet_entry.get_input_stream.read)
      REXML::XPath.match(sheet, "//*[local-name()='row']").map do |row|
        cells = []
        REXML::XPath.match(row, "*[local-name()='c']").each do |cell|
          index = xlsx_column_index(cell.attributes["r"])
          cells[index] = xlsx_cell_value(cell, shared_strings)
        end
        cells
      end
    end
  end

  def self.xlsx_shared_strings(zip)
    entry = zip.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    document = REXML::Document.new(entry.get_input_stream.read)
    REXML::XPath.match(document, "//*[local-name()='si']").map do |item|
      REXML::XPath.match(item, ".//*[local-name()='t']").map(&:text).join
    end
  end

  def self.xlsx_cell_value(cell, shared_strings)
    value = REXML::XPath.first(cell, "*[local-name()='v']")&.text
    inline = REXML::XPath.match(cell, "*[local-name()='is']//*[local-name()='t']").map(&:text).join
    return inline if inline.present?
    return if value.blank?

    cell.attributes["t"] == "s" ? shared_strings[value.to_i] : value
  end

  def self.xlsx_column_index(reference)
    letters = reference.to_s[/[A-Z]+/]
    return 0 if letters.blank?

    letters.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
  end

  def self.column_for_header(header)
    HEADER_ALIASES[normalized_header(header)]
  end

  def self.attributes_from_row(row, attributes_by_index)
    attributes_by_index.each_with_index.each_with_object({}) do |(column, index), attrs|
      next unless column

      attrs[column] = cast_import_value(column, row[index])
    end
  end

  def self.cast_import_value(column, value)
    value = value.to_s.strip if value.is_a?(String)
    return if value.blank?

    return parse_decimal(value) if DECIMAL_COLUMNS.include?(column)
    return value.to_i if INTEGER_COLUMNS.include?(column)
    return parse_date(value) if DATE_COLUMNS.include?(column)

    value
  end

  def self.parse_decimal(value)
    BigDecimal(value.to_s.delete(","))
  rescue ArgumentError
    nil
  end

  def self.parse_date(value)
    return value.to_date if value.respond_to?(:to_date)
    return excel_serial_date(value) if value.to_s.match?(/\A\d+(\.\d+)?\z/)

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def self.excel_serial_date(value)
    Date.new(1899, 12, 30) + value.to_f
  end

  def self.normalized_header(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end

  private

  def default_status
    self.status = "Active" if status.blank?
  end
end
