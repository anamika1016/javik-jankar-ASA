require "test_helper"

# Training Form List must be scoped to the login. Admin sees everything; an FCO
# or Agronomist only sees their own office's records.
class TrainingFormListScopeTest < ActionDispatch::IntegrationTest
  setup do
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Training Form List"], "can_view" => "Yes", "status" => "Active"
    })

    @mine = ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "September", "fco_name" => "FCO-Ratlam",
      "gram_name" => "MINE_RATLAM_RECORD", "trainer_name" => "Narsingh"
    })
    @theirs = ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "September", "fco_name" => "FCO-Sausar",
      "gram_name" => "THEIRS_SAUSAR_RECORD", "trainer_name" => "Someone Else"
    })
  end

  def login(user)
    post login_path, params: { login: user.user_name, password: "secret" }
  end

  test "an admin sees every training record" do
    admin = User.create!(user_name: "tfl_admin", password: "secret", first_name: "Adm",
                         user_type: "admin", status: "Active")
    login(admin)

    get module_path("training-form-list")
    assert_response :success
    assert_includes response.body, "MINE_RATLAM_RECORD"
    assert_includes response.body, "THEIRS_SAUSAR_RECORD"
  end

  test "an FCO login only sees its own office's training records" do
    fco = User.create!(user_name: "tfl_fco_ratlam", password: "secret", first_name: "Mukesh",
                       last_name: "Tomar", role: "FCO-Ratlam", office_name: "FCO-Ratlam",
                       user_type: "User", status: "Active")
    login(fco)

    get module_path("training-form-list")
    assert_response :success
    assert_includes response.body, "MINE_RATLAM_RECORD",
      "the FCO should see their own office's record"
    assert_not_includes response.body, "THEIRS_SAUSAR_RECORD",
      "the FCO must not see another office's training record"
  end

  test "an Agronomist login only sees its own office's training records" do
    agro = User.create!(user_name: "tfl_agro_ratlam", password: "secret", first_name: "Agro",
                        last_name: "Ratlam", role: "Agronomist", stakeholder_role: "Agronomist",
                        office_name: "FCO-Ratlam", user_type: "User", status: "Active")
    login(agro)

    get module_path("training-form-list")
    assert_response :success
    assert_not_includes response.body, "THEIRS_SAUSAR_RECORD",
      "an Agronomist must not see another office's training record"
  end

  # An empty cluster mapping must stay empty. It used to fall back to "every VRP
  # that has a target mapping", which showed one CC the whole organisation.
  test "a cluster incharge with no mapped JJ does not see another CC's records" do
    other_vrp = Vrp.create!(
      name: "Other JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "9876543210", email: "other#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, password: "secret",
      cluster_incharge: "Someone Else (Cluster Incharge)"
    )
    TargetMapping.create!(vrp_id: other_vrp.id, fco_id: "1", ics_id: "1", village_id: "1",
                          month_name: "September", main_activity_name: "Farmers' Training",
                          activity_name: "A", target_quantity: 1, afl_ids: "[]")
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "September", "select_vrp" => other_vrp.id.to_s,
      "gram_name" => "OTHER_CC_RECORD", "fco_name" => "FCO-Elsewhere"
    })

    lonely_cc = User.create!(user_name: "tfl_lonely_cc", password: "secret",
                             first_name: "Lonely", last_name: "CC",
                             role: "Cluster Incharge", office_name: "FCO-Nowhere",
                             user_type: "User", status: "Active")
    login(lonely_cc)

    get module_path("training-form-list")
    assert_response :success
    assert_not_includes response.body, "OTHER_CC_RECORD",
      "a CC with no mapped JJ must not inherit every VRP that has a target mapping"
    assert_not_includes response.body, "MINE_RATLAM_RECORD"
  end

  test "an unrelated login sees neither office's records" do
    other = User.create!(user_name: "tfl_outsider", password: "secret", first_name: "Out",
                         last_name: "Sider", role: "Manager ics", office_name: "PAPL",
                         user_type: "User", status: "Active")
    login(other)

    get module_path("training-form-list")
    assert_response :success
    assert_not_includes response.body, "MINE_RATLAM_RECORD"
    assert_not_includes response.body, "THEIRS_SAUSAR_RECORD"
  end
end
