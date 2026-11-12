require "csv"
require "zip"
require "rexml/document"

# Reads the bulk payment sheet uploaded on "Jeevika Jankar Payment List Detail"
# and turns it into per-bill payment rows. It only parses and validates the
# sheet; ModulesController decides which bills are payable and saves records.
#
# Columns are matched by header text (case/space insensitive), so the user can
# reorder columns or keep the extra read-only ones from the downloaded format.
class JeevikaPaymentBulkUpload
  HEADERS = {
    bill_id: ["bill id"],
    transaction_id: ["transaction id"],
    transaction_type: ["transaction type"],
    transaction_date: ["transaction date"]
  }.freeze

  Row = Struct.new(:row_number, :bill_id, :transaction_id, :transaction_type, :transaction_date, keyword_init: true)

  attr_reader :errors

  def initialize(file, transaction_types:)
    @file = file
    @transaction_types = transaction_types
    @errors = []
  end

  # Returns rows that carry payment details. Rows whose transaction columns are
  # all blank are pending payments and are skipped without an error.
  def rows
    @rows ||= parse_rows
  end

  private

  def parse_rows
    table = raw_rows
    header_index = table.index { |row| header_row?(row) }
    unless header_index
      @errors << "Excel me 'Bill ID', 'Transaction ID', 'Transaction Type' aur 'Transaction Date' columns hone chahiye."
      return []
    end

    columns = column_positions(table[header_index])
    table.each_with_index.drop(header_index + 1).filter_map do |cells, index|
      build_row(cells, columns, index + 1)
    end
  rescue Zip::Error, REXML::ParseException, CSV::MalformedCSVError, ArgumentError => e
    @errors << "Excel file read nahi ho payi: #{e.message}"
    []
  end

  def build_row(cells, columns, row_number)
    values = columns.transform_values { |position| clean(cells[position]) }
    return nil if values.values.all?(&:blank?)

    payment_values = values.slice(:transaction_id, :transaction_type, :transaction_date)
    return nil if payment_values.values.all?(&:blank?)

    row_errors = []
    row_errors << "Bill ID khali hai" if values[:bill_id].blank?
    row_errors << "Transaction ID khali hai" if values[:transaction_id].blank?

    type = values[:transaction_type].to_s.upcase
    if type.blank?
      row_errors << "Transaction Type khali hai"
    elsif !@transaction_types.include?(type)
      row_errors << "Transaction Type #{@transaction_types.join('/')} me se hona chahiye"
    end

    date = parse_date(values[:transaction_date])
    if values[:transaction_date].blank?
      row_errors << "Transaction Date khali hai"
    elsif date.nil?
      row_errors << "Transaction Date '#{values[:transaction_date]}' DD/MM/YYYY format me nahi hai (jaise 05/11/2026)"
    end

    if row_errors.any?
      @errors << "Row #{row_number}: #{row_errors.to_sentence}."
      return nil
    end

    Row.new(
      row_number: row_number,
      bill_id: normalize_id(values[:bill_id]),
      transaction_id: values[:transaction_id],
      transaction_type: type,
      transaction_date: date.iso8601
    )
  end

  def raw_rows
    case File.extname(@file.original_filename.to_s).downcase
    when ".csv"
      CSV.parse(File.read(@file.path, encoding: "bom|utf-8"))
    when ".xlsx"
      xlsx_rows(@file.path)
    else
      raise ArgumentError, "sirf .xlsx ya .csv file upload karein"
    end
  end

  def header_row?(row)
    keys = Array(row).map { |cell| header_key(cell) }
    HEADERS.values.all? { |names| (names & keys).any? }
  end

  def column_positions(row)
    keys = Array(row).map { |cell| header_key(cell) }
    HEADERS.transform_values { |names| keys.index { |key| names.include?(key) } }
  end

  def header_key(value)
    value.to_s.downcase.gsub(/\(.*?\)/, "").gsub(/[^a-z0-9]+/, " ").strip
  end

  def clean(value)
    value.to_s.strip.presence
  end

  # Excel turns a numeric Bill ID into "181646" or "181646.0".
  def normalize_id(value)
    value.to_s.strip.sub(/\.0+\z/, "")
  end

  # Only DD/MM/YYYY is accepted (e.g. 05/11/2026), the same rule the
  # downloaded Excel enforces. Anything else - 5/11/2026, 2026-11-05,
  # 05-11-2026, an Excel date number, or an impossible date like 31/02/2026 -
  # is an error, so a day and month can never be read the wrong way round.
  def parse_date(value)
    match = value.to_s.strip.match(%r{\A(\d{2})/(\d{2})/(\d{4})\z})
    return nil unless match

    Date.new(match[3].to_i, match[2].to_i, match[1].to_i)
  rescue Date::Error
    nil
  end

  def xlsx_rows(path)
    Zip::File.open(path) do |zip|
      shared_strings = xlsx_shared_strings(zip)
      sheet_entry = zip.find_entry("xl/worksheets/sheet1.xml") ||
        zip.entries.select { |entry| entry.name.match?(%r{\Axl/worksheets/[^/]+\.xml\z}) }.min_by(&:name)
      raise ArgumentError, "Excel ki pehli sheet nahi mili" unless sheet_entry

      sheet = REXML::Document.new(sheet_entry.get_input_stream.read)
      REXML::XPath.match(sheet, "//*[local-name()='sheetData']/*[local-name()='row']").map do |row|
        cells = []
        REXML::XPath.match(row, "*[local-name()='c']").each do |cell|
          cells[xlsx_column_index(cell.attributes["r"], cells.size)] = xlsx_cell_value(cell, shared_strings)
        end
        cells
      end
    end
  end

  def xlsx_shared_strings(zip)
    entry = zip.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    document = REXML::Document.new(entry.get_input_stream.read)
    REXML::XPath.match(document, "//*[local-name()='si']").map do |item|
      REXML::XPath.match(item, ".//*[local-name()='t']").map(&:text).join
    end
  end

  def xlsx_cell_value(cell, shared_strings)
    inline = REXML::XPath.match(cell, "*[local-name()='is']//*[local-name()='t']").map(&:text).join
    return inline if inline.present?

    value = REXML::XPath.first(cell, "*[local-name()='v']")&.text
    return if value.blank?

    cell.attributes["t"] == "s" ? shared_strings[value.to_i] : value
  end

  def xlsx_column_index(reference, fallback)
    letters = reference.to_s[/[A-Z]+/]
    return fallback if letters.blank?

    letters.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
  end
end
