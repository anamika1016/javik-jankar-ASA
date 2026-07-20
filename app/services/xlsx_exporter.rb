require "cgi"
require "csv"
require "time"
require "zip"

class XlsxExporter
  MIME_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

  def self.generate(headers:, rows:, sheet_name: "Sheet1")
    new(headers: headers, rows: rows, sheet_name: sheet_name).generate
  end

  def self.from_csv(csv_data, sheet_name: "Sheet1")
    table = CSV.parse(csv_data.to_s)
    generate(headers: table.shift || [], rows: table, sheet_name: sheet_name)
  end

  def initialize(headers:, rows:, sheet_name:)
    @headers = Array(headers)
    @rows = Array(rows)
    @sheet_name = safe_sheet_name(sheet_name)
  end

  def generate
    buffer = Zip::OutputStream.write_buffer do |zip|
      write_entry(zip, "[Content_Types].xml", content_types_xml)
      write_entry(zip, "_rels/.rels", root_rels_xml)
      write_entry(zip, "docProps/app.xml", app_props_xml)
      write_entry(zip, "docProps/core.xml", core_props_xml)
      write_entry(zip, "xl/workbook.xml", workbook_xml)
      write_entry(zip, "xl/_rels/workbook.xml.rels", workbook_rels_xml)
      write_entry(zip, "xl/styles.xml", styles_xml)
      write_entry(zip, "xl/worksheets/sheet1.xml", worksheet_xml)
    end

    buffer.string
  end

  private

  def write_entry(zip, path, contents)
    zip.put_next_entry(path)
    zip.write(contents)
  end

  def worksheet_xml
    rows = [@headers] + @rows
    dimension = "A1:#{cell_reference([@headers.size, rows.map { |row| Array(row).size }.max.to_i].max, rows.size)}"

    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <dimension ref="#{dimension}"/>
        <sheetViews><sheetView workbookViewId="0"/></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        <sheetData>
          #{sheet_rows_xml(rows)}
        </sheetData>
      </worksheet>
    XML
  end

  def sheet_rows_xml(rows)
    rows.map.with_index(1) do |row, row_number|
      cells = Array(row).map.with_index(1) do |value, column_number|
        cell_xml(value, row_number, column_number)
      end.join
      %(<row r="#{row_number}">#{cells}</row>)
    end.join("\n")
  end

  def cell_xml(value, row_number, column_number)
    ref = cell_reference(column_number, row_number)
    value = value.respond_to?(:strftime) ? value.strftime("%Y-%m-%d %H:%M:%S") : value.to_s
    %(<c r="#{ref}" t="inlineStr"><is><t>#{escape_xml(value)}</t></is></c>)
  end

  def cell_reference(column_number, row_number)
    "#{column_name(column_number)}#{row_number}"
  end

  def column_name(number)
    number = number.to_i
    return "A" if number <= 0

    name = +""
    while number.positive?
      number -= 1
      name.prepend((65 + (number % 26)).chr)
      number /= 26
    end
    name
  end

  def escape_xml(value)
    CGI.escapeHTML(value.to_s).gsub("\n", "&#10;")
  end

  def safe_sheet_name(value)
    name = value.to_s.gsub(/[\[\]\*\/\\\?:]/, " ").strip.gsub(/\s+/, " ")[0, 31]
    name.empty? ? "Sheet1" : name
  end

  def content_types_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      </Types>
    XML
  end

  def root_rels_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
      </Relationships>
    XML
  end

  def workbook_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
          <sheet name="#{escape_xml(@sheet_name)}" sheetId="1" r:id="rId1"/>
        </sheets>
      </workbook>
    XML
  end

  def workbook_rels_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      </Relationships>
    XML
  end

  def styles_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
      </styleSheet>
    XML
  end

  def app_props_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        <Application>VRP</Application>
      </Properties>
    XML
  end

  def core_props_xml
    timestamp = Time.now.utc.iso8601

    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:creator>VRP</dc:creator>
        <cp:lastModifiedBy>VRP</cp:lastModifiedBy>
        <dcterms:created xsi:type="dcterms:W3CDTF">#{timestamp}</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">#{timestamp}</dcterms:modified>
      </cp:coreProperties>
    XML
  end
end
