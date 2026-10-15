require "test_helper"

# The training form offers every farmer the target's villages hold today, not
# only the ones picked when the target was mapped. The mapped quantity is the
# target; it does not cap who the Jeevika Jankar may say they trained.
class Api::V1::FarmerTrainingVillageFarmersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(first_name: "Ft", last_name: "Admin", user_name: "ftv_admin",
      email: "ftv_admin@example.com", mobile_no: "9876800001", password: "secret",
      user_type: "admin", status: "Active")
    post api_v1_login_path, params: { login: "ftv_admin", password: "secret" }, as: :json
    @token = response.parsed_body["token"]
  end

  test "a farmer who registered after the mapping is still offered" do
    target
    later = farmer("Later Farmer")

    body = farmer_list

    assert_equal ["Later Farmer", "Mapped One", "Mapped Two"],
      body["farmers"].map { |row| row["farmer_name"] }.sort
    assert_equal later.id.to_s,
      body["farmers"].find { |row| row["farmer_name"] == "Later Farmer" }["id"]
  end

  test "the mapped farmers are flagged apart from the rest of the village" do
    target
    farmer("Later Farmer")

    rows = farmer_list["farmers"]

    assert_equal true, rows.find { |row| row["farmer_name"] == "Mapped One" }["is_target"]
    assert_equal false, rows.find { |row| row["farmer_name"] == "Later Farmer" }["is_target"]
    assert_equal 2, farmer_list["target_farmer_count"]
    assert_equal 1, farmer_list["other_village_farmer_count"]
  end

  test "the mapped target itself is left alone" do
    target
    farmer("Later Farmer")
    farmer_list

    assert_equal 2, target.reload.afl_ids.size, "offering the village must not remap the target"
  end

  test "a farmer from another village is not offered" do
    target
    Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Elsewhere",
      farmer_name: "Other Village Farmer", village_id: "9999", village_name: "Elsewhere")

    assert_not_includes farmer_list["farmers"].map { |row| row["farmer_name"] },
      "Other Village Farmer"
  end

  test "a farmer already trained for this activity drops off the list" do
    target
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "main_activity" => "Farmers' Training", "sub_activity" => "FFS",
      "selected_farmer_ids" => [mapped_one.id.to_s]
    })

    body = farmer_list

    assert_not_includes body["farmers"].map { |row| row["farmer_name"] }, "Mapped One"
    assert_includes body["completed_farmer_ids"], mapped_one.id.to_s
  end

  test "the mapped farmer list reports the same village farmers" do
    target
    farmer("Later Farmer")

    get "/api/v1/farmer-trainings/mapped-farmers", params: filters,
      headers: auth_headers, as: :json
    assert_response :success
    body = response.parsed_body

    assert_equal 3, body["count"]
    assert_equal 2, body["target_farmer_count"]
    assert_equal 1, body["other_village_farmer_count"]
    assert_equal 3, body["available_count"]
  end

  # The filters are what keep the lookup to the villages actually in play.
  test "another month's village is not pulled in" do
    target
    other = TargetMapping.create!(vrp: jeevika_jankar, fco_id: "13", fco_name: "Betul-FCO",
      ics_id: "39", ics_name: "Athner", village_id: "9999", village_name: "Elsewhere",
      month_name: "November", main_activity_name: "Farmers' Training", activity_name: "FFS",
      afl_ids: [], farmer_count: 0, target_quantity: 10,
      completion_date: Date.new(2026, 11, 30), created_by_type: "User", created_by_id: @admin.id)
    Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Elsewhere",
      farmer_name: "November Farmer", village_id: "9999", village_name: "Elsewhere")

    body = farmer_list

    assert_not_includes body["farmers"].map { |row| row["farmer_name"] }, "November Farmer"
    assert_not_includes body["target_mapping_ids"], other.id.to_s
  end

  def filters
    { month: "October", ics: "Athner", village: "Khairi",
      main_activity: "Farmers' Training", sub_activity: "FFS" }
  end

  def farmer_list
    get "/api/v1/farmer-trainings/farmers", params: filters, headers: auth_headers, as: :json
    assert_response :success
    response.parsed_body
  end

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def jeevika_jankar
    @jeevika_jankar ||= Vrp.create!(name: "Ftv JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B", branch: "Br",
      ifsc_code: "TEST0123456", address: "A", mobile_no: "9876800002",
      email: "ftv@example.com", experience_in_years: 1, office_detail_id: 0,
      to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, user_name: "ftv_jj", password: "secret")
  end

  def farmer(name)
    Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Athner",
      farmer_name: name, village_id: "3155", village_name: "Khairi")
  end

  def mapped_one
    @mapped_one ||= farmer("Mapped One")
  end

  def mapped_two
    @mapped_two ||= farmer("Mapped Two")
  end

  def target
    @target ||= TargetMapping.create!(vrp: jeevika_jankar, fco_id: "13", fco_name: "Betul-FCO",
      ics_id: "39", ics_name: "Athner", village_id: "3155", village_name: "Khairi",
      month_name: "October", main_activity_name: "Farmers' Training", activity_name: "FFS",
      afl_ids: [mapped_one.id, mapped_two.id], farmer_count: 2, target_quantity: 2,
      completion_date: Date.new(2026, 10, 31), created_by_type: "User", created_by_id: @admin.id)
  end
end
