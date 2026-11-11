require "test_helper"
require_relative "../support/farmer_api_stubs"

# The two Farmer 360 screens actually render, with the columns the page is
# supposed to show.
class FarmerPagesRenderTest < ActionDispatch::IntegrationTest
  include FarmerApiStubs

  REGISTER_FARMER = {
    "id" => 5,
    "full_name" => "Pooja",
    "father_husband_name" => "Jay",
    "mobile_no" => "7898071513",
    "aadhaar_no" => "111122223333",
    "is_lead_farmer" => false,
    "document_pdf" => nil,
    "aadhaar_card_image" => ["https://asa.ploughmanagro.com/doc.jpg"],
    "land_details" => [{ "id" => 2, "state_id" => 1, "district_id" => 36,
                         "block_id" => 90, "village_id" => 10143, "area" => 235.0 }]
  }.freeze

  setup do
    @admin = User.create!(user_name: "farmer_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  test "the login list shows the farmer, how they signed in, when, and from where" do
    FarmerAppLogin.record_login!(
      farmer: REGISTER_FARMER, identifier_type: "aadhaar", aadhaar_no: "111122223333",
      ip: "49.36.10.22", device: "Redmi Note 12", app_version: "1.0.3",
      latitude: 23.2250491, longitude: 74.8512613, place: "Bhawanipatna, Odisha"
    )
    FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "aadhaar")

    get farmer_app_logins_path(date: "all")
    assert_response :success

    assert_select "h1", text: "Farmer App Logins"
    assert_select ".farmer-stat-value", text: "1"
    assert_select "td", text: /Pooja/
    assert_select ".farmer-method.aadhaar", text: /Aadhaar/
    # Masked, never the full number.
    assert_includes response.body, "******1513"
    assert_includes response.body, "XXXX-XXXX-3333"
    refute_includes response.body, "7898071513"
    refute_includes response.body, "111122223333"
    # Where it came from.
    assert_includes response.body, "49.36.10.22"
    assert_includes response.body, "Bhawanipatna, Odisha"
    assert_includes response.body, "Redmi Note 12"
    assert_select "a[href*='maps.google.com']"
    # The handset is not reported here, so the column says so rather than
    # presenting the HTTP library as a device.
    assert_select ".muted-note", text: /Not reported by app/, count: 0
    assert_select "td", text: /Redmi Note 12/
    # The OTP column was removed from the list.
    assert_select "th", text: "Last OTP", count: 0
  end

  test "an HTTP library is never shown as the device" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile",
      device: "okhttp/4.9.2", ip: "49.36.10.22")

    get farmer_app_logins_path
    assert_response :success
    assert_select ".muted-note", text: /Not reported by app/
    # The HTTP library is noise on screen; it belongs only in the export.
    refute_includes response.body, "okhttp/4.9.2"
  end

  test "the export still records the HTTP client for debugging" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile",
      device: "okhttp/4.9.2")
    controller = FarmerAppLoginsController.new
    controller.instance_variable_set(:@otp_status, {})
    controller.instance_variable_set(:@locks, {})

    row = controller.send(:export_row, FarmerAppLogin.first, 0)
    headers = FarmerAppLoginsController::EXPORT_HEADERS
    assert_nil row[headers.index("Device")], "an HTTP library is not a device"
    assert_equal "okhttp/4.9.2", row[headers.index("HTTP Client")]
  end

  test "the two login counts are separate columns, not one number with a hint" do
    2.times { FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile") }
    travel_to(2.days.ago) do
      FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    end

    get farmer_app_logins_path
    assert_response :success
    assert_select "th", text: "Logins on This Date"
    assert_select "th", text: "Total Logins"
    # Two today, three all time.
    assert_select "tbody tr td", text: "2"
    assert_select "tbody tr td", text: "3"

    # Across all dates only the all-time column makes sense.
    get farmer_app_logins_path(date: "all")
    assert_response :success
    assert_select "th", text: "Logins on This Date", count: 0
    assert_select "th", text: "Total Logins"
  end

  test "every export column has a header" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    controller = FarmerAppLoginsController.new
    controller.instance_variable_set(:@otp_status, {})
    controller.instance_variable_set(:@locks, {})

    row = controller.send(:export_row, FarmerAppLogin.first, 0)
    assert_equal FarmerAppLoginsController::EXPORT_HEADERS.size, row.size
  end

  test "a login with no GPS says the app did not share it" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile", ip: "49.36.10.22")

    get farmer_app_logins_path
    assert_response :success
    assert_select ".muted-note", text: /GPS not shared by app/
    assert_select "a[href*='maps.google.com']", count: 0
  end

  test "the list never prints an OTP code" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")

    get farmer_app_logins_path(date: "all")
    assert_response :success
    refute_includes response.body, issued[:otp]
  end

  test "a locked mobile is flagged on the list" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    (FarmerLoginLock::MAX_WRONG_ATTEMPTS + 1).times { FarmerLoginLock.register_failure!("7898071513") }

    get farmer_app_logins_path(date: "all")
    assert_response :success
    assert_select ".status-pill.inactive", text: /Locked/
  end

  test "the mobile and Aadhaar tiles filter the list" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "aadhaar",
      aadhaar_no: "111122223333")

    get farmer_app_logins_path(date: "all", method: "mobile")
    assert_response :success
    assert_select "td", text: /Pooja/, count: 0

    get farmer_app_logins_path(date: "all", method: "aadhaar")
    assert_response :success
    assert_select "td", text: /Pooja/
  end

  test "an empty list explains itself instead of showing a bare table" do
    get farmer_app_logins_path(date: "all")
    assert_response :success
    assert_select ".farmer-empty", text: /No farmer has signed in/
    assert_select "table.farmer-login-table", count: 0
  end

  test "the export sheet carries the list, with mobile and Aadhaar still masked" do
    FarmerAppLogin.record_login!(
      farmer: REGISTER_FARMER, identifier_type: "aadhaar", aadhaar_no: "111122223333",
      ip: "49.36.10.22", device: "Redmi Note 12", app_version: "1.0.3",
      latitude: 23.2250491, longitude: 74.8512613, place: "Bhawanipatna, Odisha"
    )

    get export_farmer_app_logins_path(date: "all")
    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type
    assert_match(/farmer-app-logins-.*\.xlsx/, response.headers["Content-Disposition"])
    assert response.body.bytesize.positive?
  end

  test "the export follows the filter rather than dumping everything" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "aadhaar",
      aadhaar_no: "111122223333")

    rows = nil
    FarmerAppLoginsController.class_eval do
      alias_method :__original_export_row, :export_row
      define_method(:export_row) { |record, index| rows = (rows || []) << record; __original_export_row(record, index) }
    end

    begin
      get export_farmer_app_logins_path(date: "all", method: "mobile")
      assert_response :success
      assert_nil rows, "an aadhaar login must not appear in a mobile-filtered export"

      get export_farmer_app_logins_path(date: "all", method: "aadhaar")
      assert_response :success
      assert_equal 1, rows&.size
    ensure
      FarmerAppLoginsController.class_eval do
        remove_method :export_row
        alias_method :export_row, :__original_export_row
        remove_method :__original_export_row
        private :export_row
      end
    end
  end

  test "the sidebar shows Farmer 360 last, under JJ Exam, with the renamed link" do
    titles = ApplicationHelper::SIDEBAR_SECTIONS.map { |section| section[:title] }
    assert_equal "Farmer 360", titles.last
    assert_equal "JJ Exam", titles[-2]

    farmer_section = ApplicationHelper::SIDEBAR_SECTIONS.last
    assert_equal ["Farmer 360 Details", "Farmer App Logins", "Farmer News", "Farmer Videos"],
      farmer_section[:links].map(&:first)
  end

  test "renaming the Farmer 360 link did not change the permission it needs" do
    helper = Object.new.extend(ApplicationHelper)
    assert_equal "farmer-360", helper.sidebar_access_key(["Farmer 360 Details", :route, :farmer360_path])
    # A permission saved under either spelling still opens the page.
    assert_includes helper.sidebar_access_name_keys("Farmer 360"), "farmer-360-details"
    assert_includes helper.sidebar_access_name_keys("Farmer 360 Details"), "farmer-360"
  end

  test "the page opens on today and shows only today's logins" do
    today = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    older = travel_to(3.days.ago) do
      FarmerAppLogin.record_login!(
        farmer: REGISTER_FARMER.merge("id" => 9, "full_name" => "Ramesh", "mobile_no" => "9000000001",
          "aadhaar_no" => "444455556666"),
        identifier_type: "mobile"
      )
    end

    get farmer_app_logins_path
    assert_response :success
    assert_select "td", text: /#{today.full_name}/
    assert_select "td", text: /#{older.full_name}/, count: 0
    assert_select "h1", text: "Farmer App Logins"
  end

  test "picking a past date shows that day, even for a farmer who logged in again later" do
    travel_to(3.days.ago) do
      FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    end
    # The same farmer signs in again today; the summary row now points at today.
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "aadhaar",
      aadhaar_no: "111122223333")
    assert_equal 1, FarmerAppLogin.count

    get farmer_app_logins_path(date: 3.days.ago.to_date.to_s)
    assert_response :success
    assert_select "td", text: /Pooja/
    # That day's own method and count, not the latest.
    assert_select ".farmer-method.mobile", text: /Mobile/
  end

  test "a date with no logins says so instead of falling back to everything" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")

    get farmer_app_logins_path(date: 10.days.ago.to_date.to_s)
    assert_response :success
    assert_select ".farmer-empty", text: /No farmer signed in on/
    assert_select "table.farmer-login-table", count: 0
  end

  test "All Dates brings back every farmer regardless of when they signed in" do
    travel_to(5.days.ago) do
      FarmerAppLogin.record_login!(
        farmer: REGISTER_FARMER.merge("id" => 9, "full_name" => "Ramesh", "mobile_no" => "9000000001",
          "aadhaar_no" => "444455556666"),
        identifier_type: "mobile"
      )
    end
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")

    get farmer_app_logins_path(date: "all")
    assert_response :success
    assert_select "td", text: /Pooja/
    assert_select "td", text: /Ramesh/
  end

  test "the date tile counts that date's logins, not the farmer's lifetime total" do
    3.times { FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile") }
    travel_to(2.days.ago) do
      FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    end

    get farmer_app_logins_path
    assert_response :success
    # One farmer, three of their four logins fall on today.
    assert_select ".farmer-stat", text: /1\s*Farmers on this date/
    assert_select ".farmer-stat", text: /3\s*Total Logins/
  end

  test "an unreadable date falls back to today rather than showing everything" do
    travel_to(4.days.ago) do
      FarmerAppLogin.record_login!(
        farmer: REGISTER_FARMER.merge("id" => 9, "full_name" => "Ramesh", "mobile_no" => "9000000001",
          "aadhaar_no" => "444455556666"),
        identifier_type: "mobile"
      )
    end

    get farmer_app_logins_path(date: "not-a-date")
    assert_response :success
    assert_select "td", text: /Ramesh/, count: 0
  end

  test "the export filename and contents follow the chosen date" do
    travel_to(2.days.ago) do
      FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    end

    chosen = 2.days.ago.to_date
    get export_farmer_app_logins_path(date: chosen.to_s)
    assert_response :success
    assert_match(/farmer-app-logins-#{chosen.strftime('%d-%m-%Y')}\.xlsx/, response.headers["Content-Disposition"])

    get export_farmer_app_logins_path(date: "all")
    assert_response :success
    assert_match(/farmer-app-logins-all-dates\.xlsx/, response.headers["Content-Disposition"])
  end

  test "Farmer 360 renders a register record as readable fields" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do
      get farmer360_path(mobile_no: "7898071513")
    end

    assert_response :success
    assert_select "h2", text: "Pooja"
    assert_select ".farmer-detail-label", text: "Father Husband Name"
    assert_select ".farmer-detail-value", text: "Jay"
    # Booleans and nulls read as words, not as "false" and blank.
    assert_select ".farmer-detail-value", text: "No"
    assert_select ".farmer-detail-value", text: "-"
    # Nested rows get their own table.
    assert_select "h2", text: /Land Details/
    assert_select "table.module-table td", text: "235.0"
  end

  test "Farmer 360 refuses an impossible mobile number without calling the register" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |_sent, register_calls|
      get farmer360_path(mobile_no: "1234567890")
      assert_empty register_calls
    end

    assert_response :success
    assert_select ".farmer-empty", text: FarmerAppLogin::INVALID_MOBILE_MESSAGE
  end

  # All four Farmer 360 screens share one form and filter vocabulary. These
  # pin it down so a later edit cannot quietly go back to the old layout.
  test "the four Farmer 360 screens use the same form and filter markup" do
    FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")

    [farmer360_path, farmer_app_logins_path, farmer_news_index_path, farmer_videos_path].each do |path|
      get path
      assert_response :success, "#{path} should render"
      assert_select ".module-hero h1", { count: 1 }, "#{path} needs one page heading"
      refute_includes response.body, "farmer-search-field",
        "#{path} still uses the retired flex field class"
      refute_includes response.body, "farmer-date-quick",
        "#{path} still uses the retired date button row"
    end
  end

  test "the publish forms lay fields out on the shared grid, in named sections" do
    get farmer_videos_path
    assert_response :success

    assert_select "form.farmer-form .farmer-form-grid"
    assert_select ".farmer-form-section-title", text: "What the farmer sees"
    assert_select ".farmer-form-section-title", text: "Who sees it, and when"
    assert_select ".farmer-form-section-title", text: "The video — link or file"
    # Fields carry an explicit width rather than being squeezed by flex-wrap.
    assert_select ".farmer-field.span-12"
    assert_select ".farmer-field.span-6"
    assert_select ".farmer-field.span-4"
  end

  test "the state filter is a select plus two chips, not a wall of buttons" do
    get farmer_news_index_path
    assert_response :success

    assert_select ".farmer-filter-form select[name=state]"
    assert_select ".farmer-filter-chips .farmer-chip", count: 2
    # Eight states belong inside the select, not as eight separate links.
    assert_select ".farmer-filter-chips a", text: "Madhya Pradesh", count: 0
  end

  test "Farmer 360 opens with just the search form" do
    get farmer360_path
    assert_response :success
    assert_select "input[name=mobile_no]"
    assert_select "input[name=aadhaar_no]"
    assert_select ".farmer-detail-grid", count: 0
  end
end
