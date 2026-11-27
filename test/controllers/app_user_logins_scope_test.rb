require "test_helper"

# JJ App Login Detail listed every sign-in to every login, so an FCO office saw
# the whole organisation's people - and the People / Total Logins tiles counted
# them too. An office must only see its own, the same rule AgreementVrpScope
# applies everywhere else, and a Jeevika Jankar only their own sign-ins.
class AppUserLoginsScopeTest < ActionDispatch::IntegrationTest
  setup do
    @mandla_staff = User.create!(user_name: "mandla_fco", password: "secret",
      first_name: "Mandla", last_name: "FCO", role: "FCO-Mandla",
      office_name: "FCO-Mandla", user_type: "User", status: "Active")
    @admin = User.create!(user_name: "logins_admin", password: "secret",
      first_name: "Adm", user_type: "admin", status: "Active")

    @mine = login_row(name: "MANDLA JJ", record_type: "Vrp", record_id: 501,
      fcoc: "FCO-Mandla")
    # Same office, spelled the way the older imports spell it. office_key folds
    # both onto one key, so this must be visible as well.
    @mine_alias = login_row(name: "MANDLA ALIAS", record_type: "Vrp", record_id: 502,
      fcoc: "Mandla")
    @mine_staff = login_row(name: "MANDLA STAFF", record_type: "User", record_id: 503,
      fcoc: nil, office_name: "FCO-Mandla")
    @theirs = login_row(name: "BHAWANIPATNA JJ", record_type: "Vrp", record_id: 601,
      fcoc: "FCO-Bhawanipatna")
  end

  def login_row(name:, record_type:, record_id:, fcoc: nil, office_name: nil)
    AppUserLogin.create!(name: name, username: name.parameterize,
      record_type: record_type, record_id: record_id, fcoc: fcoc,
      office_name: office_name, logged_in_at: Time.current)
  end

  def sign_in(user)
    post login_path, params: { login: user.user_name, password: "secret" }
  end

  def page(params = {})
    get app_user_logins_path(**{ date: "all" }.merge(params))
    assert_response :success
    response.body
  end

  test "an FCO office does not see another office's sign-ins" do
    sign_in(@mandla_staff)

    body = page

    assert_not_includes body, "BHAWANIPATNA JJ",
      "the FCO was shown a sign-in belonging to a different office"
  end

  test "an FCO office still sees its own, however the office is spelled" do
    sign_in(@mandla_staff)

    body = page

    assert_includes body, "MANDLA JJ"
    assert_includes body, "MANDLA ALIAS", "FCO-Mandla and Mandla are the same office"
    assert_includes body, "MANDLA STAFF", "staff rows carry the office in office_name"
  end

  test "the counters count only what the office may see" do
    sign_in(@mandla_staff)
    page

    summary = @controller.view_assigns["summary"]

    assert_equal 3, summary[:logins], "Total Logins must exclude the other office"
    assert_equal 3, summary[:people]
    assert_equal 2, summary[:jeevika_jankars]
    assert_equal 1, summary[:staff]
  end

  # apply_search adds a string OR condition, and the office filter is built with
  # .or on top of it. If those two did not compose, searching would either lose
  # the office limit or blow up.
  test "searching still stays inside the office" do
    sign_in(@mandla_staff)

    body = page(q: "JJ")

    assert_includes body, "MANDLA JJ"
    assert_not_includes body, "BHAWANIPATNA JJ",
      "search reached past the office limit"
  end

  test "a search that only matches another office returns nothing" do
    sign_in(@mandla_staff)

    body = page(q: "BHAWANIPATNA")

    assert_not_includes body, "BHAWANIPATNA JJ"
  end

  # Rows saved before the office columns were filled carry neither value. They
  # belong to no office, so only an admin sees them.
  test "a sign-in with no office is not shown to an office login" do
    login_row(name: "NO OFFICE ROW", record_type: "Vrp", record_id: 701)
    sign_in(@mandla_staff)

    assert_not_includes page, "NO OFFICE ROW"
  end

  test "an admin still sees a sign-in with no office" do
    login_row(name: "NO OFFICE ROW", record_type: "Vrp", record_id: 701)
    sign_in(@admin)

    assert_includes page, "NO OFFICE ROW"
  end

  # A staff login can carry its office in fcoc rather than office_name;
  # AgreementVrpScope reads both, so the page has to as well.
  test "a login whose office is held in fcoc is scoped the same way" do
    # A new-user registration keeps its office in data["fcoc"], and that is what
    # reaches the session payload. AgreementVrpScope reads it, so the page must
    # limit on it too.
    ModuleRecord.create!(module_slug: "new-user", data: {
      "user_name" => "mandla_fcoc", "password" => "secret", "name" => "Mandla FCOC",
      "fcoc" => "FCO-Mandla", "status" => "Active"
    })
    post login_path, params: { login: "mandla_fcoc", password: "secret" }

    body = page

    assert_includes body, "MANDLA JJ"
    assert_not_includes body, "BHAWANIPATNA JJ",
      "an fcoc-held office did not limit the list"
  end

  test "an admin still sees every office" do
    sign_in(@admin)

    body = page

    assert_includes body, "MANDLA JJ"
    assert_includes body, "BHAWANIPATNA JJ"
    assert_equal 4, @controller.view_assigns["summary"][:logins]
  end

  test "a Jeevika Jankar sees only their own sign-ins" do
    jj = Vrp.create!(
      name: "Login JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "441234567890", account_no: "4412345678", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "9440000001", email: "login_jj@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, password: "secret",
      user_name: "login_jj", fcoc: "FCO-Mandla",
      # A Jeevika Jankar is held at the agreement screen until they accept, so
      # this one is past that gate and can reach the page at all.
      agreement_accepted_at: Time.current
    )
    login_row(name: "MY OWN LOGIN", record_type: "Vrp", record_id: jj.id, fcoc: "FCO-Mandla")
    post login_path, params: { login: jj.user_name, password: "secret" }

    body = page

    assert_includes body, "MY OWN LOGIN"
    assert_not_includes body, "MANDLA JJ",
      "a Jeevika Jankar must not see the rest of the office's sign-ins"
    assert_not_includes body, "BHAWANIPATNA JJ"
  end

  test "the export is scoped the same way as the page" do
    sign_in(@mandla_staff)

    get export_app_user_logins_path(date: "all")

    assert_response :success
    assert_not_includes response.body, "BHAWANIPATNA JJ",
      "the export leaked rows the page itself hides"
  end
end
