require "test_helper"

# Jeevika Jankar registration cascades State -> District -> Block -> Gram
# Panchayat -> Village. Each level must return EVERY entry its parent has in the
# LG Directory, with no cap, and must never leak another state's entries.
class VrpLocationCascadeTest < ActionDispatch::IntegrationTest
  setup do
    # Two districts under one state, so "only one came back" is a real failure.
    directory("MADHYA PRADESH", "Shahdol",   "Sohagpur", "GP Sohagpur", "Vill Sohagpur")
    directory("MADHYA PRADESH", "Shahdol",   "Jaitpur",  "GP Jaitpur",  "Vill Jaitpur")
    directory("MADHYA PRADESH", "Chhindwara", "Sausar",  "GP Sausar",   "Vill Sausar")
    directory("Odisha",         "Balangir",  "Titlagarh", "GP Titlagarh", "Vill Titlagarh")

    admin = User.create!(user_name: "loc_admin", password: "secret", first_name: "Adm",
                         user_type: "admin", status: "Active")
    post login_path, params: { login: admin.user_name, password: "secret" }
  end

  def directory(state, district, block, gp, village)
    ModuleRecord.create!(module_slug: "lg-directory-list", data: {
      "state_name" => state, "district_name" => district,
      "cd_block_name" => block, "gram_panchayat" => gp,
      "village_name" => village, "status" => "Active"
    })
  end

  def options_for(level, params = {})
    get location_options_vrps_path(params.merge(level: level)), as: :json
    assert_response :success
    JSON.parse(response.body).fetch("options").map { |option| option["value"] }
  end

  test "every state in the directory is offered" do
    states = options_for("state")
    assert_includes states, "MADHYA PRADESH"
    assert_includes states, "Odisha"
  end

  test "a state returns all of its districts, not just the first" do
    districts = options_for("district", state: "MADHYA PRADESH")
    assert_includes districts, "Shahdol"
    assert_includes districts, "Chhindwara"
    assert_not_includes districts, "Balangir", "another state's district must not appear"
  end

  test "a district returns all of its blocks" do
    blocks = options_for("block", state: "MADHYA PRADESH", district: "Shahdol")
    assert_includes blocks, "Sohagpur"
    assert_includes blocks, "Jaitpur"
    assert_not_includes blocks, "Sausar", "another district's block must not appear"
  end

  test "a block returns its gram panchayats and a gram panchayat its villages" do
    gps = options_for("gram-panchayat", state: "MADHYA PRADESH", district: "Shahdol", block: "Sohagpur")
    assert_includes gps, "GP Sohagpur"
    assert_not_includes gps, "GP Jaitpur"

    villages = options_for("village", state: "MADHYA PRADESH", district: "Shahdol",
                           block: "Sohagpur", gram_panchayat: "GP Sohagpur")
    assert_includes villages, "Vill Sohagpur"
    assert_not_includes villages, "Vill Jaitpur"
  end

  # The directory stores the state upper-cased; the form posts it however the
  # option was rendered, so matching has to ignore case.
  test "the parent match ignores case" do
    assert_includes options_for("district", state: "madhya pradesh"), "Shahdol"
    assert_includes options_for("district", state: "Madhya Pradesh"), "Chhindwara"
  end

  # An inactive directory row is excluded, but that must not empty the level.
  test "an inactive row is skipped without hiding its siblings" do
    ModuleRecord.create!(module_slug: "lg-directory-list", data: {
      "state_name" => "MADHYA PRADESH", "district_name" => "Retired District",
      "cd_block_name" => "B", "gram_panchayat" => "G", "village_name" => "V",
      "status" => "Inactive"
    })

    districts = options_for("district", state: "MADHYA PRADESH")
    assert_not_includes districts, "Retired District"
    assert_includes districts, "Shahdol"
    assert_includes districts, "Chhindwara"
  end
end
