require "test_helper"

# The dashboard report lists used to render every matching row into the page and
# let the browser paginate. The Farmer List is the whole farmer master, so that
# built a multi-megabyte page to display 25 rows. Paging happens on the server
# now; the export still carries everything.
class DashboardReportListPagingTest < ActionDispatch::IntegrationTest
  PAGE_SIZE = DashboardReportsController::REPORT_LIST_PAGE_SIZE

  setup do
    @admin = User.create!(user_name: "paging_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    ModuleRecord.create!(module_slug: "access-control",
      data: { "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active" })
    @total = (PAGE_SIZE * 2) + 7
    @total.times do |index|
      Afl.create!(fco_id: "995", fco: "Bhawanipatna",
        ics_id: "ics-#{index}", ics_name: "ICS #{index}",
        village_id: "v-#{index}", village_name: "Village #{index}",
        tracenet_no: "FARMER-#{index}", farmer_name: "Farmer #{index}")
    end
    login(@admin)
  end

  test "the first page carries one page of rows, not the whole table" do
    get dashboard_report_list_path("farmers", month: "")
    assert_response :success
    assert_select "tbody tr", PAGE_SIZE
    # The separators around "·" are non-breaking spaces, which Ruby's \s does
    # not match.
    assert_select ".module-card > p", text: /Total: #{@total}[[:space:]]*·[[:space:]]*Showing 1–#{PAGE_SIZE}/
  end

  test "paging walks the rows without repeating or skipping any" do
    seen = []
    (1..3).each do |page|
      get dashboard_report_list_path("farmers", month: "", page: page)
      assert_response :success
      seen += css_select("tbody tr td:nth-child(7)").map(&:text)
    end
    assert_equal @total, seen.size
    assert_equal @total, seen.uniq.size, "a row must not appear on two pages"
  end

  test "an out-of-range page clamps to the last one rather than coming up empty" do
    get dashboard_report_list_path("farmers", month: "", page: 9999)
    assert_response :success
    assert_select "tbody tr", @total % PAGE_SIZE
    assert_select ".report-pager .table-action.active", text: "3"
  end

  test "a page below one clamps to the first" do
    get dashboard_report_list_path("farmers", month: "", page: -5)
    assert_response :success
    assert_select ".report-pager .table-action.active", text: "1"
  end

  test "a list that fits on one page shows no pager" do
    get dashboard_report_list_path("main-indicators", month: "")
    assert_response :success
    assert_select ".report-pager", 0
  end

  test "the server-paged table drops the browser paginator that would fight it" do
    get dashboard_report_list_path("farmers", month: "")
    assert_response :success
    assert_select "#dashboard_report_table[data-paginated-table]", 0
    assert_select ".table-pagination", 0
    assert_select "[data-table-search]", 0
  end

  test "the export carries every row, not just the page on screen" do
    get dashboard_report_list_path("farmers", month: "", format: :xlsx)
    assert_response :success
    sheet = xlsx_text
    # First, last and a middle row all present, so nothing was sliced away.
    ["FARMER-0", "FARMER-#{PAGE_SIZE + 3}", "FARMER-#{@total - 1}"].each do |tracenet|
      assert_includes sheet, tracenet
    end
  end

  test "the export link and Back link do not carry the page along" do
    get dashboard_report_list_path("farmers", month: "", page: 2)
    assert_response :success
    assert_select "a[data-report-export]" do |links|
      assert_no_match(/page=/, links.first["href"])
    end
    assert_select ".dashboard-actions a", text: "Back to Dashboard" do |links|
      assert_no_match(/page=/, links.first["href"])
    end
  end

  test "the search filters every record, not only the visible page" do
    get dashboard_report_list_path("farmers", month: "", search: "FARMER-#{@total - 1}")
    assert_response :success
    assert_select "tbody tr", 1
    assert_select ".report-pager", 0
  end

  private

  def login(user)
    post login_path, params: { login: user.user_name, password: "secret" }
  end

  def xlsx_text
    result = nil
    Zip::File.open_buffer(response.body) do |zip|
      result = zip.glob("xl/worksheets/*.xml").map { |entry| entry.get_input_stream.read }.join(" ")
    end
    result
  end
end
