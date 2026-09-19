require "csv"
require "rexml/document"
require "zip"

class JjQuizQuestionImporter
  HEADER_ALIASES = {
    "question" => :question_text,
    "questiontext" => :question_text,
    "optiona" => :option_a,
    "a" => :option_a,
    "optionb" => :option_b,
    "b" => :option_b,
    "optionc" => :option_c,
    "c" => :option_c,
    "optiond" => :option_d,
    "d" => :option_d,
    "correctoption" => :correct_option,
    "correctanswer" => :correct_option,
    "answer" => :correct_option
  }.freeze

  REQUIRED_COLUMNS = %i[question_text option_a option_b correct_option].freeze

  def self.import(file:, quiz:)
    new(file: file, quiz: quiz).import
  end

  def initialize(file:, quiz:)
    @file = file
    @quiz = quiz
    @next_position = @quiz.questions.maximum(:position).to_i + 1
  end

  def import
    raise ArgumentError, "Please choose an Excel or CSV file." unless @file.present?

    rows = rows_from_upload
    headers = rows.shift
    raise ArgumentError, "Uploaded file is blank." if headers.blank?

    columns = headers.map { |header| HEADER_ALIASES[normalized_header(header)] }
    missing = REQUIRED_COLUMNS - columns.compact
    raise ArgumentError, "Excel is missing required header(s): #{missing.map { |key| JjQuizQuestion::HEADER_LABELS[key] }.join(', ')}." if missing.any?

    imported = 0
    skipped = []

    rows.each_with_index do |row, index|
      attrs = attributes_from_row(row, columns)
      next if attrs.values.all?(&:blank?)

      attrs[:correct_option] = normalize_correct_option(attrs)
      attrs[:position] = @next_position
      question = @quiz.questions.new(attrs)
      if question.save
        imported += 1
        @next_position += 1
      else
        skipped << "Row #{index + 2}: #{question.errors.full_messages.to_sentence}"
      end
    end

    raise ArgumentError, "No valid questions found in uploaded file." if imported.zero?

    { imported: imported, skipped: skipped }
  end

  private

  def rows_from_upload
    case File.extname(@file.original_filename.to_s).downcase
    when ".csv"
      CSV.read(@file.path, headers: false)
    when ".xlsx"
      rows_from_xlsx(@file.path)
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
    inline = REXML::XPath.match(cell, "*[local-name()='is']//*[local-name()='t']").map(&:text).join
    return inline if inline.present?

    value = REXML::XPath.first(cell, "*[local-name()='v']")&.text
    return if value.blank?

    cell.attributes["t"] == "s" ? shared_strings[value.to_i] : value
  end

  def xlsx_column_index(reference)
    letters = reference.to_s[/[A-Z]+/]
    return 0 if letters.blank?

    letters.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
  end

  def attributes_from_row(row, columns)
    columns.each_with_index.each_with_object({}) do |(column, index), attrs|
      next unless column

      value = row[index]
      value = value.to_s.strip if value.is_a?(String)
      attrs[column] = cast_value(column, value)
    end
  end

  def cast_value(column, value)
    return if value.blank?

    case column
    when :marks
      BigDecimal(value.to_s.delete(","))
    when :position
      value.to_i
    when :status
      value.to_s.downcase == "inactive" ? "inactive" : "active"
    else
      value
    end
  rescue ArgumentError
    nil
  end

  def normalize_correct_option(attrs)
    raw = attrs[:correct_option].to_s.strip
    option = raw.upcase.first
    return option if JjQuizQuestion::OPTIONS.include?(option)

    JjQuizQuestion::OPTIONS.find do |letter|
      attrs[:"option_#{letter.downcase}"].to_s.strip.casecmp(raw).zero?
    end || raw
  end

  def normalized_header(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end
end
