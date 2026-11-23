require "test_helper"

# Who signed in from the Jeevika Jankar / staff mobile app. Nothing recorded
# this before: the API handed out a token and kept no trace.
class AppUserLoginDetailTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "login_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    @staff = User.create!(user_name: "cc_user", password: "secret", first_name: "Arti",
      last_name: "Sharma", role: "Cluster Coordinator", office_name: "FCO-Bhawanipatna",
      user_type: "User", status: "Active")
  end

  # --- the API records the login ----------------------------------------

  test "a staff login from the app is recorded with who, when and from where" do
    assert_difference -> { AppUserLogin.count }, 1 do
      post "/api/v1/login",
        params: { login: @staff.user_name, password: "secret" }.to_json,
        headers: { "Content-Type" => "application/json",
                   "X-Device-Name" => "Redmi Note 12", "X-App-Version" => "2.1.0" }
    end

    assert_response :success
    login = AppUserLogin.sole
    assert_equal "User", login.record_type
    assert_equal @staff.id, login.record_id
    assert_equal "Arti Sharma", login.name
    assert_equal "cc_user", login.username
    assert_equal "Cluster Coordinator", login.role
    assert_equal "FCO-Bhawanipatna", login.office_name
    assert_equal "password", login.login_method
    assert_equal "Redmi Note 12", login.device
    assert_equal "2.1.0", login.app_version
    assert login.ip.present?
    assert login.logged_in_at.present?
  end

  test "a failed login is not recorded" do
    assert_no_difference -> { AppUserLogin.count } do
      post "/api/v1/login", params: { login: @staff.user_name, password: "wrong" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
  end

  test "every sign-in is its own row, so the same person shows up each time" do
    3.times do
      post "/api/v1/login", params: { login: @staff.user_name, password: "secret" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_equal 3, AppUserLogin.count
    assert_equal 1, AppUserLogin.distinct.count(:record_id)
  end

  # Logging in must never fail because the log table did.
  test "a login still succeeds when recording it raises" do
    AppUserLogin.stub_record_failure do
      assert_no_difference -> { AppUserLogin.count } do
        post "/api/v1/login", params: { login: @staff.user_name, password: "secret" }.to_json,
          headers: { "Content-Type" => "application/json" }
      end
    end

    assert_response :success
    assert JSON.parse(response.body)["token"].present?
  end

  # --- the web list -------------------------------------------------------

  test "the page opens on today and shows only today's logins" do
    today = record_login(@staff, name: "Arti Sharma")
    older = travel_to(3.days.ago) { record_login(@staff, name: "Arti Sharma") }

    sign_in_admin
    get app_user_logins_path
    assert_response :success

    assert_select "h1", text: "JJ App Login Detail"
    assert_select "td", text: /Arti Sharma/
    assert_equal 1, AppUserLogin.on_date(Date.current).count
    assert_not_equal today.id, older.id
  end

  test "picking a past date shows that day" do
    travel_to(3.days.ago) { record_login(@staff, name: "Arti Sharma") }
    record_login(@staff, name: "Arti Sharma")

    sign_in_admin
    get app_user_logins_path(view: "day", date: 3.days.ago.to_date.to_s)
    assert_response :success
    assert_select "td", text: /Arti Sharma/
    assert_select ".farmer-stat", text: /1\s*Total Logins/
  end

  test "a date with no login says so instead of falling back to everything" do
    record_login(@staff, name: "Arti Sharma")

    sign_in_admin
    get app_user_logins_path(view: "day", date: 10.days.ago.to_date.to_s)
    assert_response :success
    assert_select ".farmer-empty", text: /Nobody signed in from the mobile app in/
    assert_select "table.farmer-login-table", count: 0
  end

  test "All Dates brings back every login" do
    travel_to(5.days.ago) { record_login(@staff, name: "Arti Sharma") }
    record_login(@staff, name: "Arti Sharma", record_type: "Vrp", role: "Jeevika Jankar")

    sign_in_admin
    get app_user_logins_path(view: "all")
    assert_response :success
    assert_select ".farmer-stat", text: /2\s*Total Logins/
  end

  test "Jeevika Jankar and staff are counted and filtered apart" do
    record_login(@staff, name: "Arti Sharma")
    record_login(@staff, name: "Pinki Parihar", record_type: "Vrp", role: "Jeevika Jankar")

    sign_in_admin
    get app_user_logins_path
    assert_select ".farmer-stat", text: /1\s*Jeevika Jankar/
    assert_select ".farmer-stat", text: /1\s*Staff Users/

    get app_user_logins_path(kind: "Vrp")
    assert_select "td", text: /Pinki Parihar/
    assert_select "td", text: /Arti Sharma/, count: 0
  end

  test "the mobile number is masked on the screen" do
    record_login(@staff, name: "Arti Sharma", mobile_no: "9876543210")

    sign_in_admin
    get app_user_logins_path
    assert_response :success
    assert_includes response.body, "******3210"
    refute_includes response.body, "9876543210"
  end

  test "the export follows the chosen date and names the file after it" do
    chosen = 2.days.ago.to_date
    travel_to(chosen) { record_login(@staff, name: "Arti Sharma") }

    sign_in_admin
    get export_app_user_logins_path(view: "day", date: chosen.to_s)
    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type
    assert_match(/app-login-detail-#{chosen.strftime('%d-%m-%Y')}\.xlsx/,
      response.headers["Content-Disposition"])
  end

  # A User has office_name and no fcoc column; a Vrp has fcoc and none of the
  # others. Reading only one of them left the Office / FCO column blank for
  # half the rows, on screen and in the export.
  test "a Jeevika Jankar's FCO fills the office column" do
    AppUserLogin.record!(
      payload: { "id" => 7, "record_type" => "Vrp", "name" => "Pinki Parihar",
                 "username" => "pinki", "fcoc" => "FCO-Sausar" },
      method: :password
    )

    login = AppUserLogin.sole
    assert_equal "FCO-Sausar", login.office_name
    assert_equal "FCO-Sausar", login.fcoc
    assert_equal "FCO-Sausar", login.office_label
    # The same name must not be printed twice in one cell.
    assert_nil login.fcoc_sub_label

    sign_in_admin
    get app_user_logins_path
    assert_response :success
    assert_equal 1, response.body.scan("FCO-Sausar").size
  end

  test "a staff user's office fills the office column, through a real login" do
    post "/api/v1/login", params: { login: @staff.user_name, password: "secret" }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :success

    login = AppUserLogin.sole
    assert_equal "FCO-Bhawanipatna", login.office_name
    assert_equal "FCO-Bhawanipatna", login.office_label

    sign_in_admin
    get app_user_logins_path
    assert_select "td", text: /FCO-Bhawanipatna/
  end

  test "an office and a different FCO are both shown" do
    AppUserLogin.record!(
      payload: { "id" => 8, "record_type" => "User", "name" => "Mixed User",
                 "office_name" => "TO-Narla", "fcoc" => "FCO-Bhawanipatna" },
      method: :password
    )

    login = AppUserLogin.sole
    assert_equal "TO-Narla", login.office_label
    assert_equal "FCO-Bhawanipatna", login.fcoc_sub_label
  end

  test "the export carries the office for both kinds of user" do
    AppUserLogin.record!(
      payload: { "id" => 9, "record_type" => "Vrp", "name" => "Pinki Parihar",
                 "fcoc" => "FCO-Sausar" },
      method: :password
    )
    controller = AppUserLoginsController.new
    headers = AppUserLoginsController::EXPORT_HEADERS

    row = controller.send(:export_row, AppUserLogin.first, 0)
    assert_equal "FCO-Sausar", row[headers.index("Office")]
    assert_equal "FCO-Sausar", row[headers.index("FCO")]
  end

  test "a month shows that whole month and nothing outside it" do
    travel_to(Date.new(2026, 10, 5)) { record_login(@staff, name: "October Login") }
    travel_to(Date.new(2026, 10, 28)) { record_login(@staff, name: "Also October") }
    travel_to(Date.new(2026, 11, 3)) { record_login(@staff, name: "November Login") }

    sign_in_admin
    get app_user_logins_path(view: "month", month: "2026-10")
    assert_response :success

    assert_select "td", text: /October Login/
    assert_select "td", text: /Also October/
    assert_select "td", text: /November Login/, count: 0
    assert_select ".farmer-stat", text: /2\s*Total Logins/
  end

  test "an unreadable month falls back to this month, not to everything" do
    travel_to(6.months.ago) { record_login(@staff, name: "Long Ago") }
    record_login(@staff, name: "Recent")

    sign_in_admin
    get app_user_logins_path(view: "month", month: "not-a-month")
    assert_response :success
    assert_select "td", text: /Recent/
    assert_select "td", text: /Long Ago/, count: 0
  end

  test "Day, Month and All are offered as one choice" do
    sign_in_admin
    get app_user_logins_path

    assert_select ".login-range-modes .farmer-chip", count: 3
    assert_select ".login-range-modes .farmer-chip.is-on", text: "Day"
    # Only the chosen mode's own input is shown.
    assert_select "input[type=date]"
    assert_select "input[type=month]", count: 0
  end

  test "the month export is named after the month, and All after all dates" do
    travel_to(Date.new(2026, 10, 5)) { record_login(@staff, name: "October Login") }
    sign_in_admin

    get export_app_user_logins_path(view: "month", month: "2026-10")
    assert_response :success
    assert_match(/app-login-detail-october-2026\.xlsx/, response.headers["Content-Disposition"])

    get export_app_user_logins_path(view: "all")
    assert_response :success
    assert_match(/app-login-detail-all-dates\.xlsx/, response.headers["Content-Disposition"])
  end

  test "searching keeps the chosen month instead of jumping back to today" do
    travel_to(Date.new(2026, 10, 5)) { record_login(@staff, name: "October Login") }
    sign_in_admin

    get app_user_logins_path(view: "month", month: "2026-10", q: "October")
    assert_response :success
    assert_select "td", text: /October Login/
    assert_select "input[type=month][value=?]", "2026-10"
  end

  test "every export column has a header" do
    record_login(@staff, name: "Arti Sharma")
    controller = AppUserLoginsController.new

    row = controller.send(:export_row, AppUserLogin.first, 0)
    assert_equal AppUserLoginsController::EXPORT_HEADERS.size, row.size
  end

  test "the menu sits under its own sidebar section" do
    section = ApplicationHelper::SIDEBAR_SECTIONS.find { |s| s[:title] == "Login Detail by App" }

    assert section, "the sidebar needs a Login Detail by App section"
    assert_equal ["JJ App Login Detail"], section[:links].map(&:first)
  end

  private

  def sign_in_admin
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  def record_login(user, name:, record_type: "User", role: "Cluster Coordinator", mobile_no: nil)
    AppUserLogin.record!(
      payload: { "id" => user.id, "record_type" => record_type, "name" => name,
                 "username" => user.user_name, "role" => role, "mobile_no" => mobile_no },
      method: :password
    )
  end
end

# Forces the recording to blow up, to prove a login does not depend on it.
class AppUserLogin
  def self.stub_record_failure
    singleton_class.class_eval do
      alias_method :__original_record!, :record!
      define_method(:record!) { |**| raise "log table unavailable" }
    end
    yield
  ensure
    singleton_class.class_eval do
      remove_method :record!
      alias_method :record!, :__original_record!
      remove_method :__original_record!
    end
  end
end
