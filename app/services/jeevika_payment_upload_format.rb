# The Excel format downloaded from "Jeevika Jankar Payment List Detail" for
# bulk payment upload. Same workbook as XlsxExporter, plus rules inside Excel:
#   * the transaction columns are Text, so a typed date stays "05/11/2026"
#     and a long UTR number is not turned into 1.23E+11;
#   * Transaction Type is a NEFT/RTGS/IMPS dropdown, nothing else is accepted;
#   * Transaction Date must be written as DD/MM/YYYY.
# The server checks the same rules again on upload (JeevikaPaymentBulkUpload).
class JeevikaPaymentUploadFormat < XlsxExporter
  TEXT_STYLE = 1
  HEADER_STYLE = 2
  # Leave room for rows the user adds below the downloaded ones.
  EXTRA_ROWS = 500

  def self.generate(headers:, rows:, transaction_columns:, transaction_types:, sheet_name: "Payment Upload")
    new(headers: headers, rows: rows, sheet_name: sheet_name,
        transaction_columns: transaction_columns, transaction_types: transaction_types).generate
  end

  # transaction_columns: 1-based column numbers of { id:, type:, date: }.
  def initialize(headers:, rows:, sheet_name:, transaction_columns:, transaction_types:)
    super(headers: headers, rows: rows, sheet_name: sheet_name)
    @columns = transaction_columns
    @transaction_types = transaction_types
  end

  private

  def text_column?(column_number)
    @columns.values.include?(column_number)
  end

  def last_row
    @rows.size + 1 + EXTRA_ROWS
  end

  def cell_xml(value, row_number, column_number)
    return %(<c r="#{cell_reference(column_number, row_number)}" s="#{HEADER_STYLE}" t="inlineStr"><is><t>#{escape_xml(value)}</t></is></c>) if row_number == 1
    return super unless text_column?(column_number)
    return %(<c r="#{cell_reference(column_number, row_number)}" s="#{TEXT_STYLE}"/>) if value.to_s.empty?

    %(<c r="#{cell_reference(column_number, row_number)}" s="#{TEXT_STYLE}" t="inlineStr"><is><t>#{escape_xml(value)}</t></is></c>)
  end

  def worksheet_xml
    rows = [@headers] + @rows
    dimension = "A1:#{cell_reference(@headers.size, rows.size)}"

    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <dimension ref="#{dimension}"/>
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        #{cols_xml}
        <sheetData>
          #{sheet_rows_xml(rows)}
        </sheetData>
        #{data_validations_xml}
      </worksheet>
    XML
  end

  def cols_xml
    widths = { 1 => 12, 2 => 16, 3 => 26, 4 => 14, 5 => 30, 6 => 14, 7 => 12, 8 => 14, 9 => 12 }
    cols = widths.map { |column, width| %(<col min="#{column}" max="#{column}" width="#{width}" customWidth="1"/>) }
    @columns.each_value.sort.each do |column|
      cols << %(<col min="#{column}" max="#{column}" width="26" style="#{TEXT_STYLE}" customWidth="1"/>)
    end
    "<cols>#{cols.uniq { |col| col[/min="\d+"/] }.join}</cols>"
  end

  def data_validations_xml
    type_col = column_name(@columns[:type])
    date_col = column_name(@columns[:date])
    date_cell = "#{date_col}2"
    day = "LEFT(#{date_cell},2)"
    month = "MID(#{date_cell},4,2)"
    year = "RIGHT(#{date_cell},4)"
    date_rule = "AND(LEN(#{date_cell})=10,MID(#{date_cell},3,1)=\"/\",MID(#{date_cell},6,1)=\"/\"," \
      "ISNUMBER(VALUE(#{day})),ISNUMBER(VALUE(#{month})),ISNUMBER(VALUE(#{year}))," \
      "VALUE(#{day})>=1,VALUE(#{day})<=31,VALUE(#{month})>=1,VALUE(#{month})<=12,VALUE(#{year})>=2000)"
    types = @transaction_types.join(",")

    <<~XML.strip
      <dataValidations count="2">
        <dataValidation type="list" errorStyle="stop" allowBlank="1" showInputMessage="1" showErrorMessage="1"
          errorTitle="Galat Transaction Type" error="Sirf #{escape_xml(@transaction_types.join(' / '))} me se chunein."
          promptTitle="Transaction Type" prompt="#{escape_xml(@transaction_types.join(' / '))} me se chunein."
          sqref="#{type_col}2:#{type_col}#{last_row}"><formula1>"#{escape_xml(types)}"</formula1></dataValidation>
        <dataValidation type="custom" errorStyle="stop" allowBlank="1" showInputMessage="1" showErrorMessage="1"
          errorTitle="Galat Date Format" error="Date DD/MM/YYYY format me likhein, jaise 05/11/2026."
          promptTitle="Transaction Date" prompt="DD/MM/YYYY, jaise 05/11/2026"
          sqref="#{date_col}2:#{date_col}#{last_row}"><formula1>#{escape_xml(date_rule)}</formula1></dataValidation>
      </dataValidations>
    XML
  end

  def styles_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="3">
          <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          <xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
          <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
      </styleSheet>
    XML
  end
end
