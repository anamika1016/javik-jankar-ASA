require "test_helper"

# An Agronomist (or any staff account) attached to an FCO office must see every
# Jeevika Jankar of that office, even the ones somebody else registered.
class VrpOfficeVisibilityTest < ActionDispatch::IntegrationTest
  def create_vrp(name:, fcoc:, created_by_id: 999_001)
    Vrp.create!(
      name: name, father_husband_name: "Father", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "Bank",
      branch: "Branch", ifsc_code: "TEST0123456", address: "Addr",
      mobile_no: "9876543210", email: "jj#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 10, password: "secret",
      fcoc: fcoc, created_by_id: created_by_id, created_by_type: "User"
    )
  end

  setup do
    # Same office, three different spellings that exist in real data.
    @mine_a = create_vrp(name: "Bhawanipatna JJ One", fcoc: "FCO-Bhawanipatna")
    @mine_b = create_vrp(name: "Bhawanipatna JJ Two", fcoc: "Bhawanipatna - FCO")
    @mine_c = create_vrp(name: "Bhawanipatna JJ Three", fcoc: "FCO-C Bhawanipatna")
    @other  = create_vrp(name: "Pakur JJ", fcoc: "FCO-Pakur")

    @agronomist = User.create!(
      user_name: "office_agronomist", password: "secret", first_name: "Vedantika",
      last_name: "Sadangi", role: "Agronomist", stakeholder_role: "Agronomist",
      office_name: "FCO-Bhawanipatna", status: "Active"
    )
  end

  test "an Agronomist sees every JJ of their FCO, however the office is spelled" do
    post login_path, params: { login: @agronomist.user_name, password: "secret" }
    get vrps_path
    assert_response :success

    [@mine_a, @mine_b, @mine_c].each do |vrp|
      assert_includes response.body, vrp.name, "#{vrp.fcoc} should be visible to this FCO"
    end
    assert_not_includes response.body, @other.name,
      "a different FCO's Jeevika Jankar must stay hidden"
  end

  test "the signed agreement list uses the same office scope" do
    [@mine_a, @other].each do |vrp|
      vrp.update!(agreement_accepted_at: Time.current)
    end
    post login_path, params: { login: @agronomist.user_name, password: "secret" }

    get vrp_agreements_path
    assert_response :success
    assert_includes response.body, @mine_a.name
    assert_not_includes response.body, @other.name
  end

  test "a Jeevika Jankar login is not widened to the whole office" do
    post login_path, params: { login: @mine_a.user_name.presence || @mine_a.mobile_no,
                               password: "secret" }
    get vrps_path

    # Either the JJ cannot reach the staff list at all, or it shows only itself.
    if response.successful?
      assert_not_includes response.body, @mine_b.name,
        "a JJ login must not see other Jeevika Jankars of the office"
    end
  end
end
