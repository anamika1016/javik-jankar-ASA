require "test_helper"

class Api::V1::TargetMappingsControllerTest < ActionDispatch::IntegrationTest
  test "recent target mappings require authentication" do
    get "/api/v1/target-mappings/recent", as: :json

    assert_response :unauthorized
  end

  # Picking several sub activities writes one row each, so the raw table held 34
  # rows where only 6 mappings had been made.  The app has to see what the web
  # list shows.
  test "sub activities saved together come back as one mapping" do
    jj = vrp("Sangeeta Uikey", "9876500101")
    saved_at = Time.zone.parse("2026-10-10 16:15:39")
    %w[FFS Lead\ Farmers\ Meeting Matka\ Khad].each do |sub_activity|
      mapping(jj, sub_activity, saved_at)
    end

    body = recent_as(admin)

    assert_equal 1, body["count"], "three sub activities were one submission"
    row = body["target_mappings"].first
    assert_equal "Sangeeta Uikey", row["jeevika_jankar_name"]
    assert_equal ["FFS", "Lead Farmers Meeting", "Matka Khad"], row["sub_activities"].sort
    assert_equal "FFS, Lead Farmers Meeting, Matka Khad", row["sub_activity"]
    assert_equal 3, row["target_mapping_ids"].size, "the rows behind the mapping stay addressable"
  end

  test "a sub activity mapped at another time stays its own mapping" do
    jj = vrp("Nilesh Nagwanshi", "9876500102")
    mapping(jj, "FFS", Time.zone.parse("2026-10-10 16:05:24"))
    mapping(jj, "Input Demo- Rabi Crop", Time.zone.parse("2026-10-11 09:00:00"))

    assert_equal 2, recent_as(admin)["count"]
  end

  test "each Jeevika Jankar keeps its own mapping" do
    saved_at = Time.zone.parse("2026-10-10 16:00:00")
    mapping(vrp("Sarswati Kumare", "9876500103"), "FFS", saved_at)
    mapping(vrp("Hemlata Davande", "9876500104"), "FFS", saved_at)

    body = recent_as(admin)
    assert_equal 2, body["count"]
    assert_equal ["Hemlata Davande", "Sarswati Kumare"],
      body["target_mappings"].map { |row| row["jeevika_jankar_name"] }.sort
  end

  test "the farmers of every sub activity are counted once on the mapping" do
    jj = vrp("Anita Kavadkar", "9876500105")
    shared = farmer("Shared Farmer")
    extra = farmer("Extra Farmer")
    saved_at = Time.zone.parse("2026-10-10 14:12:36")
    mapping(jj, "FFS", saved_at, afl_ids: [shared.id, extra.id])
    mapping(jj, "Lead Farmers Meeting", saved_at, afl_ids: [shared.id])

    row = recent_as(admin)["target_mappings"].first
    assert_equal 2, row["farmer_count"], "the shared farmer must not be counted twice"
    assert_equal ["Extra Farmer", "Shared Farmer"],
      row["farmers"].map { |entry| entry["farmer_name"] }.sort
  end

  test "limit counts mappings rather than the rows behind them" do
    saved_at = Time.zone.parse("2026-10-10 16:15:39")
    2.times do |index|
      jj = vrp("Limit JJ #{index}", "98765002#{index}0")
      3.times { |sub| mapping(jj, "Sub #{sub}", saved_at + index.days) }
    end

    assert_equal 1, recent_as(admin, limit: 1)["count"]
  end

  # The row cut falls mid-submission here, and a mapping missing half its sub
  # activities would be worse than one fewer mapping in the list.
  test "a mapping sitting on the row limit is not returned half read" do
    newer = vrp("Wide New JJ", "9876500301")
    older = vrp("Wide Old JJ", "9876500302")
    # Asking for 2 mappings reads 50 rows, so the older submission loses 5 of its
    # own to the newer one.
    25.times { |sub| mapping(older, "Old Sub #{sub}", Time.zone.parse("2026-10-09 10:00:00")) }
    30.times { |sub| mapping(newer, "New Sub #{sub}", Time.zone.parse("2026-10-10 10:00:00")) }

    body = recent_as(admin, limit: 2)

    assert_equal 1, body["count"], "the half read mapping is held back, not shown short"
    row = body["target_mappings"].first
    assert_equal "Wide New JJ", row["jeevika_jankar_name"]
    assert_equal 30, row["sub_activities"].size, "the newest mapping must come back whole"
  end

  test "a Jeevika Jankar only sees their own mappings" do
    mine = vrp("Mine JJ", "9876500106")
    saved_at = Time.zone.parse("2026-10-10 16:15:39")
    mapping(mine, "FFS", saved_at)
    mapping(vrp("Theirs JJ", "9876500107"), "FFS", saved_at)

    body = recent_as(mine)
    assert_equal 1, body["count"]
    assert_equal "Mine JJ", body["target_mappings"].first["jeevika_jankar_name"]
  end

  def recent_as(record, params = {})
    get "/api/v1/target-mappings/recent", params: params,
      headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(record)}" }, as: :json
    assert_response :success
    response.parsed_body
  end

  def admin
    @admin ||= User.create!(first_name: "Target", last_name: "Admin",
      user_name: "target_api_admin", email: "target_api_admin@example.com",
      mobile_no: "9876500100", password: "secret", user_type: "admin", status: "Active")
  end

  def farmer(name)
    Afl.create!(fco_id: "13", fco: "Betul-FCO", ics_id: "39", ics_name: "Athner",
      farmer_name: name, village_id: "3155", village_name: "Khairi")
  end

  def mapping(jj, sub_activity, saved_at, afl_ids: [])
    record = TargetMapping.create!(vrp: jj, fco_id: "13", fco_name: "Betul-FCO",
      ics_id: "39", ics_name: "Athner", village_id: "3155", village_name: "Khairi",
      month_name: "October", main_activity_name: "Farmers' Training",
      activity_name: sub_activity, afl_ids: afl_ids, farmer_count: afl_ids.size,
      target_quantity: 100, completion_date: Date.new(2026, 10, 31),
      created_by_type: "User", created_by_id: 1)
    # Saving a submission stamps every one of its rows at the same moment, which
    # is what ties them back together.
    record.update_columns(created_at: saved_at, updated_at: saved_at)
    record
  end

  def vrp(name, mobile)
    Vrp.create!(name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "tm#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      user_name: "tm_#{SecureRandom.hex(4)}", password: "secret")
  end
end
