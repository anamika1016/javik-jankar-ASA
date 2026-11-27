require "csv"
require "date"
require "bigdecimal"
require "set"
require "nokogiri"
require "zip"

class Afl < ApplicationRecord
  IMPORT_BATCH_SIZE = 2_000

  IMPORT_COLUMNS = %i[
    fco_id fco fpo_id fpo_name ics_id ics_name village_id village_name farm_id ginning_id broker_id farmer_name father_name
    tracenet_no total_farm_area purchase_quantity_amount estimate_quantity purchase_quantity
    purchase_date dispoce ip date estimate_quantity_admin slip_no mobile_no purchase_product
    purchase_product_type khasara_no longitude lattitude aadhar reg_type fy qr_aadhar
    qr_mobile qrcode qrcode_date status
  ].freeze

  LIST_COLUMNS = %i[
    id fco_id fco fpo_id fpo_name ics_id ics_name village_id village_name farm_id farmer_name father_name tracenet_no total_farm_area
    purchase_quantity_amount estimate_quantity purchase_quantity purchase_date mobile_no purchase_product
    status created_at
  ].freeze

  # The list table's columns and their headings, in display order. The heading
  # row, the per-column search row and the whitelist that search accepts are
  # all built from this, so a column can never show a heading it cannot be
  # searched by, or be searchable without appearing.
  LIST_HEADERS = {
    id: "ID",
    fco_id: "FCO ID",
    fco: "FCO",
    fpo_id: "FPO ID",
    fpo_name: "FPO Name",
    ics_id: "ICS ID",
    ics_name: "ICS Name/Block Name",
    village_id: "Village ID",
    village_name: "Village Name",
    farm_id: "Farm ID",
    farmer_name: "Farmer Name",
    father_name: "Father Name",
    tracenet_no: "Tracenet No",
    total_farm_area: "Total Farm Area",
    purchase_quantity_amount: "Purchase Quantity Amount",
    estimate_quantity: "Estimate Quantity",
    purchase_quantity: "Purchase Quantity",
    purchase_date: "Purchase Date",
    mobile_no: "Mobile No",
    purchase_product: "Purchase Product",
    status: "Status"
  }.freeze

  DECIMAL_COLUMNS = %i[
    total_farm_area purchase_quantity_amount estimate_quantity purchase_quantity
    estimate_quantity_admin longitude lattitude
  ].freeze

  DATE_COLUMNS = %i[purchase_date date].freeze
  DATETIME_COLUMNS = %i[qrcode_date].freeze

  HEADER_ALIASES = {
    "ID" => :id,
    "FCO_ID" => :fco_id,
    "FCO" => :fco,
    "FPO_ID" => :fpo_id,
    "FPO_Name" => :fpo_name,
    "ICS_ID" => :ics_id,
    "ICS_NAME" => :ics_name,
    "Village_ID" => :village_id,
    "Village_Name" => :village_name,
    "Farm_ID" => :farm_id,
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
    validate_import_headers!(attributes_by_index)
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
    validate_import_headers!(attributes_by_index)
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

    imported_id = import_id_from(attrs[:id])
    unless imported_id
      skipped << skipped_row(row_number, "ID must be a positive integer", attrs)
      return
    end
    attrs[:id] = imported_id

    timestamp = Time.current
    batch << [row_number, attrs.merge(created_at: timestamp, updated_at: timestamp)]
  end

  # The ID exactly as the sheet meant it, or nil when the cell is not a whole
  # positive number.
  #
  # A plain string was the only shape accepted before, which is not how Excel
  # hands a number over: a numeric cell arrives as 178203.0, and a large one is
  # written in scientific notation as "1.78203E5". Both failed the digits-only
  # check, so those rows were dropped and the ID the uploader had in their
  # sheet found nothing afterwards.
  #
  # A fraction is still refused rather than rounded -- 178203.75 is not row
  # 178203, and quietly making it one would file the data under another row's
  # ID. Same for anything non-numeric.
  def self.import_id_from(value)
    text = value.to_s.strip
    return if text.blank?

    decimal = begin
      BigDecimal(text)
    rescue ArgumentError, TypeError
      return
    end
    return unless decimal.frac.zero?

    id = decimal.to_i
    id if id.between?(1, 9_223_372_036_854_775_807)
  end

  def self.validate_import_headers!(attributes_by_index)
    raise ArgumentError, "Excel does not contain any supported AFL columns." if attributes_by_index.compact.blank?
    raise ArgumentError, "Excel is missing required header: Farmer_Name." unless attributes_by_index.include?(:farmer_name)
    raise ArgumentError, "Excel is missing required header: ID." unless attributes_by_index.include?(:id)
  end

  def self.flush_import_batch(batch, skipped)
    return 0 if batch.blank?

    # Serialize inserts briefly so the explicit imported IDs and the normal
    # PostgreSQL sequence cannot collide with another application insert.
    batch_skipped = []
    inserted_count = transaction(requires_new: true) do
      connection.execute("LOCK TABLE #{connection.quote_table_name(table_name)} IN SHARE ROW EXCLUSIVE MODE")
      advance_import_sequence!(batch.map { |_number, attrs| attrs[:id] }.max)

      unique_rows = {}
      batch.each do |row_number, attrs|
        if unique_rows.key?(attrs[:id])
          batch_skipped << skipped_row(row_number, "ID already exists", attrs)
        else
          unique_rows[attrs[:id]] = [row_number, attrs]
        end
      end
      inserted_ids = insert_all(unique_rows.values.map(&:last), unique_by: primary_key, returning: %w[id]).rows.flatten.map(&:to_i).to_set
      unique_rows.each do |id, (row_number, attrs)|
        batch_skipped << skipped_row(row_number, "ID already exists", attrs) unless inserted_ids.include?(id)
      end
      inserted_ids.size
    end
    skipped.concat(batch_skipped)
    inserted_count
  rescue ActiveRecord::RangeError, ActiveRecord::StatementInvalid => e
    insert_batch_one_by_one(batch, skipped)
  ensure
    batch.clear
  end

  def self.insert_batch_one_by_one(batch, skipped)
    imported = 0

    batch.each do |row_number, attrs|
      inserted = transaction(requires_new: true) do
        connection.execute("LOCK TABLE #{connection.quote_table_name(table_name)} IN SHARE ROW EXCLUSIVE MODE")
        advance_import_sequence!(attrs[:id])
        insert_all([attrs], unique_by: primary_key, returning: %w[id]).rows.any?
      end
      if inserted
        imported += 1
      else
        skipped << skipped_row(row_number, "ID already exists", attrs)
      end
    rescue ActiveRecord::RangeError, ActiveRecord::StatementInvalid => e
      skipped << skipped_row(row_number, e.message.to_s.split("\n").first, attrs)
    end

    imported
  end

  def self.advance_import_sequence!(max_id)
    sequence = connection.pk_and_sequence_for(table_name)&.last
    raise ActiveRecord::StatementInvalid, "AFL ID sequence is missing" if sequence.blank?

    quoted_sequence = connection.quote_table_name(sequence.to_s)
    # Never move the sequence backwards: another writer may already have
    # reserved IDs greater than the current maximum table ID.
    connection.execute("SELECT setval(#{connection.quote(sequence.to_s)}, GREATEST((SELECT last_value FROM #{quoted_sequence}), #{Integer(max_id)}), true)")
  end

  def self.column_for_header(header)
    raw_header = header.to_s.strip
    return :id if raw_header.casecmp?("id")
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

  # How a per-column filter compares, as offered in each header's dropdown.
  # The first is the default when none is chosen.
  COLUMN_OPERATORS = {
    "contains" => "Contains",
    "equals" => "Equals",
    "starts_with" => "Starts with",
    "ends_with" => "Ends with",
    "not_contains" => "Does not contain",
    "empty" => "Is empty",
    "not_empty" => "Is not empty"
  }.freeze

  DEFAULT_COLUMN_OPERATOR = "contains".freeze

  # The two operators that ask about presence rather than content, so the
  # header's text box is irrelevant to them.
  VALUELESS_COLUMN_OPERATORS = %w[empty not_empty].freeze

  # Per-header search: each entry narrows one column, and several together
  # narrow each other (FCO "Bhawanipatna" AND Status "Active"), unlike the
  # single box above which matches any column.
  #
  # Only LIST_HEADERS keys are accepted, so a request cannot reach a column the
  # table does not show, and the name is quoted rather than interpolated.
  # ::text keeps numeric, date and boolean columns searchable by what the row
  # displays -- typing "2026-06" into Purchase Date matches, where a typed
  # comparison would raise.
  def self.column_search(filters, operators = {})
    return all if filters.blank? && operators.blank?

    columns = (Array(filters&.keys) + Array(operators&.keys)).uniq
    columns.reduce(all) do |scope, column|
      key = column.to_sym
      next scope unless LIST_HEADERS.key?(key)

      operator = operators.to_h.with_indifferent_access[column].to_s.presence || DEFAULT_COLUMN_OPERATOR
      operator = DEFAULT_COLUMN_OPERATOR unless COLUMN_OPERATORS.key?(operator)
      value = filters.to_h.with_indifferent_access[column].to_s.strip
      next scope if value.blank? && VALUELESS_COLUMN_OPERATORS.exclude?(operator)

      column_search_condition(scope, key, operator, value)
    end
  end

  def self.column_search_condition(scope, column, operator, value)
    quoted = "#{connection.quote_column_name(column)}::text"
    escaped = sanitize_sql_like(value)

    case operator
    when "equals" then scope.where("#{quoted} ILIKE :value", value: escaped)
    when "starts_with" then scope.where("#{quoted} ILIKE :value", value: "#{escaped}%")
    when "ends_with" then scope.where("#{quoted} ILIKE :value", value: "%#{escaped}")
    when "not_contains"
      # A NULL column is "not containing" the text, which NOT ILIKE alone
      # would drop -- those rows do not show the value either.
      scope.where("#{quoted} IS NULL OR #{quoted} NOT ILIKE :value", value: "%#{escaped}%")
    when "empty" then scope.where("COALESCE(BTRIM(#{quoted}), '') = ''")
    when "not_empty" then scope.where("COALESCE(BTRIM(#{quoted}), '') <> ''")
    else scope.where("#{quoted} ILIKE :value", value: "%#{escaped}%")
    end
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
      id: attrs[:id],
      tracenet_no: attrs[:tracenet_no],
      longitude: attrs[:longitude],
      lattitude: attrs[:lattitude],
      khasara_no: attrs[:khasara_no],
      farmer_name: attrs[:farmer_name],
      father_name: attrs[:father_name],
      village_id: attrs[:village_id],
      village_name: attrs[:village_name],
      farm_id: attrs[:farm_id]
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

      sheet = Nokogiri::XML(sheet_entry.get_input_stream.read)
      sheet.xpath("//*[local-name()='row']").map do |row|
        cells = []
        row.xpath("./*[local-name()='c']").each do |cell|
          index = xlsx_column_index(cell["r"])
          cells[index] = xlsx_cell_value(cell, shared_strings)
        end
        cells
      end
    end
  end

  def self.xlsx_shared_strings(zip)
    entry = zip.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    document = Nokogiri::XML(entry.get_input_stream.read)
    document.xpath("//*[local-name()='si']").map do |item|
      item.xpath(".//*[local-name()='t']").map(&:text).join
    end
  end

  def self.xlsx_cell_value(cell, shared_strings)
    value = cell.at_xpath("./*[local-name()='v']")&.text
    inline = cell.xpath("./*[local-name()='is']//*[local-name()='t']").map(&:text).join
    return inline if inline.present?
    return if value.blank?

    cell["t"] == "s" ? shared_strings[value.to_i] : value
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
