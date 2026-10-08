require "test_helper"

# The transfer form stores "<name> - <mobile> - <id>" because the trailing id is
# how a saved transfer is resolved back to a Jeevika Jankar. People should only
# ever read the name and mobile.
class JeevikaJankarTransferFormTest < ActionDispatch::IntegrationTest
  def create_vrp(name:, mobile:, created_by_id: nil)
    Vrp.create!(
      name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "t#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret",
      created_by_id: created_by_id, created_by_type: created_by_id ? "User" : nil
    )
  end

  setup do
    @admin = User.create!(user_name: "jjt_admin", password: "secret", first_name: "Adm",
                          user_type: "admin", status: "Active")
    @vrp = create_vrp(name: "TAPASWINI PUJARI", mobile: "9692773069")
    post login_path, params: { login: @admin.user_name, password: "secret" }
  end

  test "the form shows name and mobile but never the raw record id" do
    get module_path("jeevika-jankar-transfer")
    assert_response :success

    option = response.body[/<option value="TAPASWINI PUJARI[^"]*"[^>]*>([^<]*)</, 1].to_s.strip
    assert_equal "TAPASWINI PUJARI - 9692773069", option,
      "the option text must not expose the trailing record id"
    assert_includes response.body, "TAPASWINI PUJARI - 9692773069 - #{@vrp.id}",
      "the stored value still carries the id used for lookup"
  end

  test "the transfer form uses the chip picker, not a raw multi-select" do
    get module_path("jeevika-jankar-transfer")
    assert_includes response.body, "data-chip-multiselect"
    assert_not_includes response.body, "Ctrl/Cmd dabakar",
      "the old multi-select hint should be gone"
  end

  test "the transfer form no longer renders a Saved Records table" do
    get module_path("jeevika-jankar-transfer")
    assert_response :success
    assert_not_includes response.body, "Saved Records"
  end

  test "the saved transfer list reads as plain names" do
    ModuleRecord.create!(module_slug: "jeevika-jankar-transfer", data: {
      "sidebar_menu" => "Target Mapping", "user_name" => "Akash Mandal",
      "jeevika_jankar_names" => ["TAPASWINI PUJARI - 9692773069 - #{@vrp.id}"],
      "status" => "Active"
    })

    get module_path("jeevika-jankar-transfer-list")
    assert_response :success

    # The picker's option values legitimately carry the id, so read the table only.
    table_only = response.body.gsub(/<option\b[^>]*>.*?<\/option>/m, "")
    assert_includes table_only, "TAPASWINI PUJARI - 9692773069"
    assert_not_includes table_only, "9692773069 - #{@vrp.id}",
      "the list must not show the trailing record id"
  end

  # The browser narrows the Jeevika Jankar list to the selected user's FCO, so
  # both dropdowns have to publish the same office key.
  test "both transfer dropdowns publish a matching office key" do
    @vrp.update!(fcoc: "FCO-C Turekela")
    User.create!(user_name: "akash_turekela", password: "secret", first_name: "Akash",
                 last_name: "Mandal", role: "FCO-C Turekela", office_name: "FCO-C Turekela",
                 user_type: "User", status: "Active")

    get module_path("jeevika-jankar-transfer")
    assert_response :success

    user_select = response.body[/<select[^>]*data-jj-transfer-user.*?<\/select>/m]
    jj_select = response.body[/<select[^>]*data-jj-transfer-jj.*?<\/select>/m]
    assert user_select, "the User Name select should carry the transfer hook"
    assert jj_select, "the Jeevika Jankar select should carry the transfer hook"

    assert_includes user_select, 'data-office="turekela"'
    assert_includes jj_select, 'data-office="turekela"',
      "the Jeevika Jankar option must expose the same key as its user's FCO"
  end

  test "a Jeevika Jankar from another office carries a different key" do
    @vrp.update!(fcoc: "FCO-C Turekela")
    other = create_vrp(name: "SAUSAR JJ", mobile: "9000000009")
    other.update!(fcoc: "FCO-C Sausar")

    get module_path("jeevika-jankar-transfer")
    jj_select = response.body[/<select[^>]*data-jj-transfer-jj.*?<\/select>/m]
    assert_includes jj_select, 'data-office="sausar"'
    assert_includes jj_select, 'data-office="turekela"'
  end

  # A transfer hands over your own registration; it must not offer everyone's.
  test "a non-admin is only offered the Jeevika Jankars they registered" do
    mine = create_vrp(name: "MINE JJ", mobile: "9000000001", created_by_id: nil)
    staff = User.create!(user_name: "jjt_staff", password: "secret", first_name: "Staff",
                         office_name: "FCO-Ratlam", user_type: "User", status: "Active")
    mine.update!(created_by_id: staff.id, created_by_type: "User")

    post login_path, params: { login: staff.user_name, password: "secret" }
    get module_path("jeevika-jankar-transfer")
    assert_response :success

    assert_includes response.body, "MINE JJ"
    assert_not_includes response.body, "TAPASWINI PUJARI",
      "someone else's Jeevika Jankar must not be transferable"
  end
end
