require "bigdecimal"
require "csv"
require "date"
require "rexml/document"
require "zip"

module TabularImportExport
  extend ActiveSupport::Concern

  included do
    before_validation :default_tabular_status, if: -> { respond_to?(:status) }
  end

  class_methods do
    def import(file)
      raise ArgumentError, "Please choose an Excel or CSV file." unless file.present?

      rows = rows_from_upload(file)
      headers = rows.shift
      raise ArgumentError, "Uploaded file is blank." if headers.blank?

      import_rows(rows, headers)
    end

    def import_rows(rows, headers)
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

    def to_csv(records = all)
      CSV.generate(headers: true) do |csv|
        csv << export_columns.map { |column| header_labels.fetch(column) }
        records.each do |record|
          csv << export_columns.map { |column| record.public_send(column) }
        end
      end
    end

    def to_xlsx(records = all)
      XlsxExporter.generate(
        headers: export_columns.map { |column| header_labels.fetch(column) },
        rows: records.map { |record| export_columns.map { |column| record.public_send(column) } },
        sheet_name: model_name.human.pluralize
      )
    end

    def export_columns
      self::EXPORT_COLUMNS
    end

    def header_labels
      self::HEADER_LABELS
    end

    def decimal_columns
      const_defined?(:DECIMAL_COLUMNS) ? self::DECIMAL_COLUMNS : []
    end

    def date_columns
      const_defined?(:DATE_COLUMNS) ? self::DATE_COLUMNS : []
    end

    def rows_from_upload(file)
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

    def rows_from_xlsx(path)
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

    def xlsx_shared_strings(zip)
      entry = zip.find_entry("xl/sharedStrings.xml")
      return [] unless entry

      document = REXML::Document.new(entry.get_input_stream.read)
      REXML::XPath.match(document, "//*[local-name()='si']").map do |item|
        REXML::XPath.match(item, ".//*[local-name()='t']").map(&:text).join
      end
    end

    def xlsx_cell_value(cell, shared_strings)
      value = REXML::XPath.first(cell, "*[local-name()='v']")&.text
      inline = REXML::XPath.match(cell, "*[local-name()='is']//*[local-name()='t']").map(&:text).join
      return inline if inline.present?
      return if value.blank?

      cell.attributes["t"] == "s" ? shared_strings[value.to_i] : value
    end

    def xlsx_column_index(reference)
      letters = reference.to_s[/[A-Z]+/]
      return 0 if letters.blank?

      letters.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
    end

    def column_for_header(header)
      header_aliases[normalized_header(header)]
    end

    def header_aliases
      header_labels.each_with_object({}) do |(column, label), aliases|
        aliases[normalized_header(label)] = column
        aliases[normalized_header(column)] = column
      end
    end

    def attributes_from_row(row, attributes_by_index)
      attributes_by_index.each_with_index.each_with_object({}) do |(column, index), attrs|
        next unless column

        attrs[column] = cast_import_value(column, row[index])
      end
    end

    def cast_import_value(column, value)
      value = value.to_s.strip if value.is_a?(String)
      return if value.blank?

      return parse_decimal(value) if decimal_columns.include?(column)
      return parse_date(value) if date_columns.include?(column)

      value
    end

    def parse_decimal(value)
      BigDecimal(value.to_s.delete(","))
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      return value.to_date if value.respond_to?(:to_date)
      return excel_serial_date(value) if value.to_s.match?(/\A\d+(\.\d+)?\z/)

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def excel_serial_date(value)
      Date.new(1899, 12, 30) + value.to_f
    end

    def normalized_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
    end
  end

  private

  def default_tabular_status
    self.status = "Active" if status.blank?
  end
end
