require "test_helper"

# JJ Mapped Farmers behaves differently per login: a Jeevika Jankar sees their
# own profile, admin picks from the external list, and a staff login picks from
# the Jeevika Jankars under them.
class JjMappedFarmersScopeTest < ActionDispatch::IntegrationTest
  setup do
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["JJ Mapped Farmers"], "can_view" => "Yes", "status" => "Active"
    })
    @staff = User.create!(user_name: "mapped_staff", password: "secret", first_name: "Shailesh",
                          last_name: "Bagde", role: "agricultural specialist",
                          office_name: "FCO-C Sausar", mobile_no: "7000280864",
                          user_type: "User", status: "Active")
    # An Agronomist works their whole FCO, so office decides, not who registered.
    @mine = vrp("MY JJ", "9000000001")
    @theirs = vrp("OTHER JJ", "9000000002", fcoc: "FCO-C Turekela")
  end

  def vrp(name, mobile, **extra)
    Vrp.create!({
      name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "m#{SecureRandom.hex(4)}@e.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: "FCO-C Sausar"
    }.merge(extra))
  end

  def jj_select
    response.body[/<select[^>]*name="mobile_no".*?<\/select>/m]
  end

  test "a staff login is not mistaken for a Jeevika Jankar login" do
    post login_path, params: { login: @staff.user_name, password: "secret" }
    get jj_mapped_farmers_path
    assert_response :success

    assert_not_includes response.body, "Logged In Jeevika Jankar",
      "a staff login must not be auto-mapped as a Jeevika Jankar"
    assert jj_select, "a staff login should get a Jeevika Jankar picker"
  end

  # An Agronomist / FCO login works their own office.
  test "an office posting lists that office's Jeevika Jankars only" do
    post login_path, params: { login: @staff.user_name, password: "secret" }
    get jj_mapped_farmers_path
    assert_response :success

    assert_includes jj_select, "MY JJ"
    assert_not_includes jj_select, "OTHER JJ",
      "another office's Jeevika Jankar must not be offered"
  end

  # A Cluster Incharge works the Jeevika Jankars mapped to them by name,
  # whatever office they sit in.
  test "a cluster incharge lists the Jeevika Jankars mapped to them" do
    cc = User.create!(user_name: "mapped_cc", password: "secret", first_name: "Dolamani",
                      last_name: "Karuan", role: "Cluster Incharge",
                      office_name: "FCO-C Sausar", user_type: "User", status: "Active")
    vrp("CLUSTER JJ", "9000000004", cluster_incharge: "Dolamani Karuan (Cluster Incharge)")
    vrp("SOMEONE ELSES JJ", "9000000005", cluster_incharge: "Other CC")

    post login_path, params: { login: cc.user_name, password: "secret" }
    get jj_mapped_farmers_path
    assert_response :success

    assert_includes jj_select, "CLUSTER JJ"
    assert_not_includes jj_select, "SOMEONE ELSES JJ",
      "another cluster incharge's Jeevika Jankar must not be offered"
    assert_not_includes jj_select, "MY JJ",
      "a cluster incharge is scoped by mapping, not by office"
  end

  test "a single Jeevika Jankar is selected without the user choosing" do
    @mine.update!(fcoc: "FCO-C Sausar")
    @theirs.update!(fcoc: "FCO-C Turekela")
    post login_path, params: { login: @staff.user_name, password: "secret" }
    get jj_mapped_farmers_path
    assert_response :success
    assert_match(/value="9000000001"[^>]*selected/, jj_select)
  end

  # Admin keeps the external list and the direct-mobile box exactly as before.
  test "admin still gets the external list and the direct mobile box" do
    User.create!(user_name: "mapped_admin", password: "secret", first_name: "Adm",
                 user_type: "admin", status: "Active")
    post login_path, params: { login: "mapped_admin", password: "secret" }

    get jj_mapped_farmers_path
    assert_response :success
    assert_includes response.body, "(API List)"
    assert_includes response.body, 'name="vrp_mobile"'
  end

  # An actual Jeevika Jankar login is auto-mapped and gets no picker.
  test "a Jeevika Jankar login stays auto-mapped" do
    vrp("LOGIN JJ", "9000000003", user_name: "login_jj",
        agreement_accepted_at: Time.current)
    post login_path, params: { login: "login_jj", password: "secret" }

    get jj_mapped_farmers_path
    assert_response :success
    assert_includes response.body, "Logged In Jeevika Jankar"
    assert_nil jj_select, "a Jeevika Jankar login should not get a picker"
  end
end
