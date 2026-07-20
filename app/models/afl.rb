require "csv"
require "date"
require "bigdecimal"
require "rexml/document"
require "zip"

class Afl < ApplicationRecord
  IMPORT_BATCH_SIZE = 2_000

  IMPORT_COLUMNS = %i[
    fco_id fco fpo_id fpo_name ics_id ics_name village_id village_name ginning_id broker_id farmer_name father_name
    tracenet_no total_farm_area purchase_quantity_amount estimate_quantity purchase_quantity
    purchase_date dispoce ip date estimate_quantity_admin slip_no mobile_no purchase_product
    purchase_product_type khasara_no longitude lattitude aadhar reg_type fy qr_aadhar
    qr_mobile qrcode qrcode_date status
  ].freeze

  LIST_COLUMNS = %i[
    id fco_id fco fpo_id fpo_name ics_id ics_name village_id village_name farmer_name father_name tracenet_no total_farm_area
    purchase_quantity_amount estimate_quantity purchase_quantity purchase_date mobile_no purchase_product
    status created_at
  ].freeze

  DECIMAL_COLUMNS = %i[
    total_farm_area purchase_quantity_amount estimate_quantity purchase_quantity
    estimate_quantity_admin longitude lattitude
  ].freeze

  DATE_COLUMNS = %i[purchase_date date].freeze
  DATETIME_COLUMNS = %i[qrcode_date].freeze

  HEADER_ALIASES = {
    "FCO_ID" => :fco_id,
    "FCO" => :fco,
    "FPO_ID" => :fpo_id,
    "FPO_Name" => :fpo_name,
    "ICS_ID" => :ics_id,
    "ICS_NAME" => :ics_name,
    "Village_ID" => :village_id,
    "Village_Name" => :village_name,
    "Ginning_Id" => :ginning_id,
    "Broker_Id" => :broker_id,
    "Farmer_Name" => :farmer_name,
    "Father_Name" => :father_name,
    "Tracenet_No" => :tracenet_no,
    "Total_Farm_Area" => :total_farm_area,
    "Purchase_Quantity_Amount" => :purchase_quantity_amount,
    "Estimate_Quantity" => :estimate_quantity,
    "Purchase_Quantity" => :purchase_quantity,
    "Purchase_Date" => :purchase_date,
    "Dispoce" => :dispoce,
    "IP" => :ip,
    "Date" => :date,
    "Estimate_Quantity_Admin" => :estimate_quantity_admin,
    "Slip_No" => :slip_no,
    "Mobile_No" => :mobile_no,
    "Purchase_Product" => :purchase_product,
    "Purchase_Product_Type" => :purchase_product_type,
    "Khasara_NO" => :khasara_no,
    "Longitude" => :longitude,
    "Lattitude" => :lattitude,
    "AAdhar" => :aadhar,
    "reg_type" => :reg_type,
    "FY" => :fy,
    "QR_AADHAR" => :qr_aadhar,
    "QR_MOBILE" => :qr_mobile,
    "QRCODE" => :qrcode,
    "QRCODE_DATE" => :qrcode_date,
    "Status" => :status
  }.freeze

  validates :farmer_name, presence: true

  def self.import(file)
    raise ArgumentError, "Please choose an Excel or CSV file." unless file.present?

    extension = File.extname(file.original_filename.to_s).downcase
    return import_csv(file.path) if extension == ".csv"

    rows = rows_from_upload(file)
    headers = rows.shift
    raise ArgumentError, "Uploaded file is blank." if headers.blank?

    import_rows(rows, headers)
  end

  def self.import_rows(rows, headers)
    attributes_by_index = headers.map { |header| column_for_header(header) }
    imported = 0
    skipped = []
    batch = []

    rows.each_with_index do |row, index|
      queue_import_row(row, index + 2, attributes_by_index, batch, skipped)
      imported += flush_import_batch(batch, skipped) if batch.size >= IMPORT_BATCH_SIZE
    end

    imported += flush_import_batch(batch, skipped)
    { imported: imported, skipped: skipped }
  end

  def self.import_csv(path)
    csv = CSV.open(path, headers: false)
    headers = csv.shift
    raise ArgumentError, "Uploaded file is blank." if headers.blank?

    attributes_by_index = headers.map { |header| column_for_header(header) }
    imported = 0
    skipped = []
    batch = []

    csv.each.with_index(2) do |row, row_number|
      queue_import_row(row, row_number, attributes_by_index, batch, skipped)
      imported += flush_import_batch(batch, skipped) if batch.size >= IMPORT_BATCH_SIZE
    end

    imported += flush_import_batch(batch, skipped)
    { imported: imported, skipped: skipped }
  ensure
    csv&.close
  end

  def self.queue_import_row(row, row_number, attributes_by_index, batch, skipped)
    attrs = attributes_from_row(row, attributes_by_index)
    return if attrs.values.all?(&:blank?)

    timestamp = Time.current
    batch << [row_number, attrs.merge(created_at: timestamp, updated_at: timestamp)]
  end

  def self.flush_import_batch(batch, skipped)
    return 0 if batch.blank?

    rows = batch.map(&:last)
    insert_all(rows)
    rows.size
  rescue ActiveRecord::RangeError, ActiveRecord::StatementInvalid => e
    insert_batch_one_by_one(batch, skipped)
  ensure
    batch.clear
  end

  def self.insert_batch_one_by_one(batch, skipped)
    imported = 0

    batch.each do |row_number, attrs|
      insert_all([attrs])
      imported += 1
    rescue ActiveRecord::RangeError, ActiveRecord::StatementInvalid => e
      skipped << skipped_row(row_number, e.message.to_s.split("\n").first, attrs)
    end

    imported
  end

  def self.column_for_header(header)
    raw_header = header.to_s.strip
    HEADER_ALIASES[raw_header] || IMPORT_COLUMNS.find { |column| normalized_header(column) == normalized_header(raw_header) }
  end

  def self.searchable_columns
    column_names.map(&:to_sym) - %i[id created_at updated_at]
  end

  def self.search(query)
    query = query.to_s.strip
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query)}%"
    where(
      searchable_columns.map { |column| "#{connection.quote_column_name(column)}::text ILIKE :query" }.join(" OR "),
      query: pattern
    )
  end

  def self.normalized_coordinate(value)
    return if value.blank?

    BigDecimal(value.to_s).round(8).to_s("F")
  rescue ArgumentError
    nil
  end

  def self.skipped_row(row_number, reason, attrs = {})
    {
      row: row_number,
      reason: reason,
      tracenet_no: attrs[:tracenet_no],
      longitude: attrs[:longitude],
      lattitude: attrs[:lattitude],
      khasara_no: attrs[:khasara_no],
      farmer_name: attrs[:farmer_name],
      father_name: attrs[:father_name],
      village_id: attrs[:village_id],
      village_name: attrs[:village_name]
    }
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
    return parse_date(value) if DATE_COLUMNS.include?(column)
    return parse_datetime(value) if DATETIME_COLUMNS.include?(column)

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

  def self.parse_datetime(value)
    return value.to_datetime if value.respond_to?(:to_datetime)
    return excel_serial_date(value).to_datetime if value.to_s.match?(/\A\d+(\.\d+)?\z/)

    DateTime.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def self.excel_serial_date(value)
    Date.new(1899, 12, 30) + value.to_f
  end

  def self.rows_from_upload(file)
    extension = File.extname(file.original_filename.to_s).downcase

    case extension
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

  def self.normalized_header(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end
end
