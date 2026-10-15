require "test_helper"

# Other Target with Farmer and its list. Only indicators set up as "Other with
# Farmer" belong on this form, and a target drops off once every farmer it was
# mapped against is done.
class Api::V1::OtherTargetWithFarmersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(first_name: "Otwf", last_name: "Admin", user_name: "otwf_admin",
      email: "otwf_admin@example.com", mobile_no: "9876700001", password: "secret",
      user_type: "admin", status: "Active")
    post api_v1_login_path, params: { login: "otwf_admin", password: "secret" }, as: :json
    @token = response.parsed_body["token"]
  end

  test "every endpoint requires authentication" do
    ["/api/v1/other-target-with-farmers", "/api/v1/other-target-with-farmers/form-data",
     "/api/v1/other-target-with-farmers/months", "/api/v1/other-target-with-farmers/farmers",
     "/api/v1/other-target-with-farmer-list"].each do |path|
      get path, as: :json
      assert_response :unauthorized, "#{path} answered without a token"
    end
  end

  test "the form offers only Other with Farmer indicators" do
    with_farmer_target
    plain_other_target

    body = get_json("/api/v1/other-target-with-farmers/form-data")

    assert_equal ["WhatsApp Group with Farmer"], body["options"]["main_activities"]
    assert_equal 1, body["count"], "the plain Other indicator must not appear here"
  end

  # The mirror of the rule above: the plain screen keeps everything else.
  test "the plain Other Target form leaves the Other with Farmer indicators out" do
    with_farmer_target
    plain_other_target

    body = get_json("/api/v1/other-targets/form-data")

    assert_equal ["Village Meeting"], body["options"]["main_activities"]
  end

  test "a target whose mapped farmers are all done drops off the form" do
    target = with_farmer_target
    ModuleRecord.create!(module_slug: "other-target-with-farmer", data: {
      "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => [farmer_one.id.to_s, farmer_two.id.to_s]
    })

    assert_equal 0, get_json("/api/v1/other-target-with-farmers/form-data")["count"]
  end

  test "a target with farmers still open stays on the form" do
    target = with_farmer_target
    ModuleRecord.create!(module_slug: "other-target-with-farmer", data: {
      "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => [farmer_one.id.to_s]
    })

    assert_equal 1, get_json("/api/v1/other-target-with-farmers/form-data")["count"]
  end

  test "the farmer list leaves out the farmers already covered" do
    target = with_farmer_target
    ModuleRecord.create!(module_slug: "other-target-with-farmer", data: {
      "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => [farmer_one.id.to_s]
    })

    body = get_json("/api/v1/other-target-with-farmers/farmers", target_mapping_id: target.id.to_s)

    assert_not_includes body["farmers"].map { |row| row["farmer_name"] }, "Farmer One"
    assert_equal [farmer_one.id.to_s], body["completed_farmer_ids"]
  end

  # The target is mapped against two farmers, but the village holds a third who
  # registered later. The web form offers all of them and the app must match.
  test "every farmer in the village is offered, not only the mapped ones" do
    target = with_farmer_target
    village_only = Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Athner",
      farmer_name: "Later Farmer", village_id: "3155", village_name: "Khairi")

    body = get_json("/api/v1/other-target-with-farmers/farmers", target_mapping_id: target.id.to_s)

    assert_equal ["Farmer One", "Farmer Two", "Later Farmer"],
      body["farmers"].map { |row| row["farmer_name"] }.sort
    assert_equal 2, body["target_farmer_count"], "two of them are the mapped target"
    assert_equal 1, body["other_village_farmer_count"]
    assert_equal target.afl_ids.size, 2, "the mapped target itself is unchanged"
    assert_equal village_only.id.to_s,
      body["farmers"].find { |row| row["farmer_name"] == "Later Farmer" }["id"]
  end

  test "a mapped farmer is flagged apart from a village farmer" do
    target = with_farmer_target
    Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Athner",
      farmer_name: "Later Farmer", village_id: "3155", village_name: "Khairi")

    rows = get_json("/api/v1/other-target-with-farmers/farmers",
      target_mapping_id: target.id.to_s)["farmers"]

    assert_equal true, rows.find { |row| row["farmer_name"] == "Farmer One" }["is_target"]
    assert_equal false, rows.find { |row| row["farmer_name"] == "Later Farmer" }["is_target"]
    assert_equal %w[Farmer\ One Farmer\ Two Later\ Farmer], rows.map { |row| row["farmer_name"] },
      "mapped farmers come first"
  end

  test "a farmer from another village is not offered" do
    target = with_farmer_target
    Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Elsewhere",
      farmer_name: "Other Village Farmer", village_id: "9999", village_name: "Elsewhere")

    body = get_json("/api/v1/other-target-with-farmers/farmers", target_mapping_id: target.id.to_s)

    assert_not_includes body["farmers"].map { |row| row["farmer_name"] }, "Other Village Farmer"
  end

  test "the farmer list needs a target to be chosen first" do
    get "/api/v1/other-target-with-farmers/farmers", headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["message"], "target_mapping_id is required"
  end

  test "a record is saved, listed and read back" do
    target = with_farmer_target

    post "/api/v1/other-target-with-farmers", params: record_params(target),
      headers: auth_headers, as: :json
    assert_response :created
    id = response.parsed_body["other_target_with_farmer"]["id"]

    body = get_json("/api/v1/other-target-with-farmers")
    assert_equal [id], body["other_target_with_farmers"].map { |row| row["id"] }

    assert_equal "2", get_json("/api/v1/other-target-with-farmers/#{id}")
      .dig("other_target_with_farmer", "data", "achievement")
  end

  test "the list route mirrors the index" do
    target = with_farmer_target
    post "/api/v1/other-target-with-farmers", params: record_params(target),
      headers: auth_headers, as: :json
    assert_response :created

    assert_equal 1, get_json("/api/v1/other-target-with-farmer-list")["count"]
  end

  test "a saved record can be edited" do
    target = with_farmer_target
    post "/api/v1/other-target-with-farmers", params: record_params(target),
      headers: auth_headers, as: :json
    assert_response :created
    record = ModuleRecord.find(response.parsed_body["other_target_with_farmer"]["id"])

    patch "/api/v1/other-target-with-farmers/#{record.id}", params: { achievement: "1" },
      headers: auth_headers, as: :json

    assert_response :success
    assert_equal "1", record.reload.data["achievement"]
  end

  test "an achievement above the target is refused" do
    target = with_farmer_target
    post "/api/v1/other-target-with-farmers",
      params: record_params(target).merge(achievement: "99"), headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].join(" "), "Achievement Target se jyada nahi ho sakta."
  end

  test "months come from the mapped targets" do
    with_farmer_target

    assert_includes get_json("/api/v1/other-target-with-farmers/months")["months"]
      .map { |month| month["name"] }, "October"
  end

  def record_params(target)
    { jeevika_jankar_id: jeevika_jankar.id.to_s, jeevika_jankar_name: jeevika_jankar.name,
      contact_number: "9876700002", month: "October", ics: "Athner", village: "Khairi",
      main_activity: "WhatsApp Group with Farmer", sub_activity: "Village group",
      training_topic: "WhatsApp Group with Farmer", training_subject: "Village group",
      completion_date: "2026-10-31", target: "2", achievement: "2",
      farmer_count: "2", selected_farmer_ids: [farmer_one.id.to_s, farmer_two.id.to_s],
      target_mapping_id: target.id.to_s }
  end

  def get_json(path, params = {})
    get path, params: params, headers: auth_headers, as: :json
    assert_response :success
    response.parsed_body
  end

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def jeevika_jankar
    @jeevika_jankar ||= Vrp.create!(name: "Otwf JJ", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B", branch: "Br",
      ifsc_code: "TEST0123456", address: "A", mobile_no: "9876700002",
      email: "otwf@example.com", experience_in_years: 1, office_detail_id: 0,
      to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, user_name: "otwf_jj", password: "secret",
      fcoc: "FCO-C Sausar")
  end

  def farmer_one
    @farmer_one ||= Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Athner",
      farmer_name: "Farmer One", village_id: "3155", village_name: "Khairi")
  end

  def farmer_two
    @farmer_two ||= Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Athner",
      farmer_name: "Farmer Two", village_id: "3155", village_name: "Khairi")
  end

  def with_farmer_target
    @with_farmer_target ||= begin
      activity_group("WhatsApp Group with Farmer", "Other with Farmer")
      mapping("WhatsApp Group with Farmer", "Village group", [farmer_one.id, farmer_two.id])
    end
  end

  def plain_other_target
    @plain_other_target ||= begin
      activity_group("Village Meeting", "Other")
      mapping("Village Meeting", "Monthly meeting", [])
    end
  end

  def activity_group(name, type)
    ModuleRecord.create!(module_slug: "add-activity-group", data: {
      "main_activity_name" => name, "main_activity_type" => type, "status" => "Active"
    })
  end

  def mapping(main_activity, sub_activity, afl_ids)
    TargetMapping.create!(vrp: jeevika_jankar, fco_id: "13", fco_name: "Betul-FCO",
      ics_id: "39", ics_name: "Athner", village_id: "3155", village_name: "Khairi",
      month_name: "October", main_activity_name: main_activity, activity_name: sub_activity,
      afl_ids: afl_ids, farmer_count: afl_ids.size, target_quantity: 2,
      completion_date: Date.new(2026, 10, 31), created_by_type: "User", created_by_id: @admin.id)
  end
end
