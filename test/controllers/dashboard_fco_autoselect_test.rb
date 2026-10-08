require "test_helper"

# A posted user never picks their FCO by hand: the dashboard offers only their
# own office and selects it. Admin keeps the whole list with "All FCO".
class DashboardFcoAutoselectTest < ActionDispatch::IntegrationTest
  setup do
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active"
    })
    %w[Sausar Turekela Bhawanipatna].each_with_index do |office, index|
      Afl.create!(fco_id: (1000 + index).to_s, fco: office, ics_id: "ics#{index}",
                  ics_name: "ICS #{office}", village_id: "v#{index}",
                  village_name: "V #{office}", farmer_name: "F #{office}",
                  tracenet_no: "T#{index}")
      vrp(office)
    end
  end

  def vrp(office)
    Vrp.create!(
      name: "JJ #{office}", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "98765432#{rand(10..99)}", email: "v#{SecureRandom.hex(4)}@e.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, password: "secret",
      fcoc: "FCO-C #{office}"
    )
  end

  def fco_select_options
    select_html = response.body[/<select[^>]*name="fcoc".*?<\/select>/m] ||
      response.body[/<select[^>]*id="dash_fcoc".*?<\/select>/m]
    assert select_html, "the dashboard should render an FCO picker"
    select_html.scan(/<option[^>]*>([^<]*)</).flatten.map(&:strip)
  end

  def selected_fco
    select_html = response.body[/<select[^>]*name="fcoc".*?<\/select>/m] ||
      response.body[/<select[^>]*id="dash_fcoc".*?<\/select>/m]
    select_html[/<option[^>]*selected[^>]*>([^<]*)</, 1]&.strip
  end

  test "a posted user is offered only their own FCO, already selected" do
    User.create!(user_name: "sausar_staff", password: "secret", first_name: "Shailesh",
                 last_name: "Bagde", role: "agricultural specialist",
                 office_name: "FCO-C Sausar", user_type: "User", status: "Active")
    post login_path, params: { login: "sausar_staff", password: "secret" }

    get dashboard_path
    assert_response :success

    options = fco_select_options
    assert_includes options.join(" "), "Sausar"
    refute_includes options.join(" "), "Turekela",
      "another office must not be offered to a posted user"
    refute_includes options.join(" "), "Bhawanipatna"
    assert_match(/Sausar/, selected_fco.to_s, "their own FCO should come pre-selected")
  end

  test "an admin still sees every FCO and defaults to All FCO" do
    User.create!(user_name: "dash_admin", password: "secret", first_name: "Adm",
                 user_type: "admin", status: "Active")
    post login_path, params: { login: "dash_admin", password: "secret" }

    get dashboard_path
    assert_response :success

    joined = fco_select_options.join(" ")
    assert_includes joined, "Sausar"
    assert_includes joined, "Turekela"
    assert_includes joined, "Bhawanipatna"
    assert_includes joined, "All FCO"
  end

  # The office is spelled "FCO-Bhawanipatna" on the login but "FCO-C Bhawanipatna"
  # on the data; both have to resolve to the same office.
  test "a differently spelled office still matches and pre-selects" do
    User.create!(user_name: "patna_staff", password: "secret", first_name: "Veda",
                 role: "Agronomist", office_name: "FCO-Bhawanipatna",
                 user_type: "User", status: "Active")
    post login_path, params: { login: "patna_staff", password: "secret" }

    get dashboard_path
    assert_response :success
    assert_match(/Bhawanipatna/, selected_fco.to_s)
    refute_includes fco_select_options.join(" "), "Sausar"
  end
end
