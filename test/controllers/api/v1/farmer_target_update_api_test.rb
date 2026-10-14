require "test_helper"

# Edit endpoints for the two app forms.  A PATCH carries only the fields that
# changed, so everything it leaves out has to survive untouched.
class Api::V1::FarmerTargetUpdateApiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(first_name: "Edit", last_name: "Admin",
      user_name: "edit_api_admin", email: "edit_api_admin@example.com",
      mobile_no: "9876511111", password: "secret", user_type: "admin", status: "Active")
    @token = login_token("edit_api_admin")
  end

  test "editing requires authentication" do
    record = training_record
    patch "/api/v1/farmer-trainings/#{record.id}", params: { male_count: "9" }, as: :json
    assert_response :unauthorized

    patch "/api/v1/other-targets/#{other_target_record.id}", params: { achievement: "4" }, as: :json
    assert_response :unauthorized
  end

  test "an unknown record is reported rather than created" do
    patch "/api/v1/farmer-trainings/999999", params: { male_count: "9" },
      headers: auth_headers, as: :json
    assert_response :not_found
    assert_equal false, response.parsed_body["success"]
  end

  test "a farmer training edit saves and recomputes the totals" do
    record = training_record

    patch "/api/v1/farmer-trainings/#{record.id}",
      params: { male_count: "9", female_count: "4", training_location: "New Hall" },
      headers: auth_headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal false, body["pending_approval"]

    data = record.reload.data
    assert_equal "9", data["male_count"]
    assert_equal "4", data["female_count"]
    assert_equal "New Hall", data["training_location"]
    assert_equal "13", data["total_farmer_count"], "total follows the edited male and female counts"
  end

  test "fields left out of a farmer training edit are kept" do
    record = training_record

    patch "/api/v1/farmer-trainings/#{record.id}", params: { male_count: "9" },
      headers: auth_headers, as: :json
    assert_response :success

    data = record.reload.data
    assert_equal ["/uploads/module_records/register.pdf"], Array(data["training_register_upload"]),
      "an upload that was not re-sent must not be wiped"
    assert_equal ["/uploads/module_records/photo.jpg"], Array(data["photo_front_view"])
    assert_equal "Hall A", data["training_location"]
    assert_equal "July", data["month"]
  end

  test "a farmer training edit cannot take the record away from its creator" do
    record = training_record
    record.update!(data: record.data.merge("created_by_id" => "4242", "created_by_name" => "Pankaj"))

    patch "/api/v1/farmer-trainings/#{record.id}",
      params: { male_count: "9", created_by_id: "1", created_by_name: "Someone Else" },
      headers: auth_headers, as: :json
    assert_response :success

    data = record.reload.data
    assert_equal "4242", data["created_by_id"]
    assert_equal "Pankaj", data["created_by_name"]
  end

  test "an invalid farmer training edit is refused and nothing is written" do
    record = training_record

    patch "/api/v1/farmer-trainings/#{record.id}", params: { male_count: "abc" },
      headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal false, body["success"]
    assert_includes body["errors"].join(" "), "Male Count"
    assert_equal "7", record.reload.data["male_count"], "the saved record stays as it was"
  end

  test "an other target edit saves the achievement" do
    record = other_target_record

    patch "/api/v1/other-targets/#{record.id}", params: { achievement: "7" },
      headers: auth_headers, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_equal "7", record.reload.data["achievement"]
  end

  test "an other target achievement above the target is refused" do
    record = other_target_record

    patch "/api/v1/other-targets/#{record.id}", params: { achievement: "99" },
      headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].join(" "), "Achievement Target se jyada nahi ho sakta."
    assert_equal "5", record.reload.data["achievement"]
  end

  test "the record id in the path is not written into the record" do
    record = other_target_record

    patch "/api/v1/other-targets/#{record.id}", params: { achievement: "7" },
      headers: auth_headers, as: :json
    assert_response :success

    assert_not record.reload.data.key?("id"), "the URL id must not become a data field"
  end

  # Someone else's record must stay out of reach, the same as on the list.
  test "a Jeevika Jankar cannot edit another Jeevika Jankar's training" do
    mine = vrp("Mine JJ", "9876511201")
    theirs = vrp("Theirs JJ", "9876511202")
    record = training_record
    record.update!(data: record.data.merge("jeevika_jankar_id" => theirs.id.to_s))

    patch "/api/v1/farmer-trainings/#{record.id}", params: { male_count: "9" },
      headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(mine)}" }, as: :json

    assert_response :not_found
    assert_equal "7", record.reload.data["male_count"]
  end

  # A cluster incharge raises a request for the Agronomist on the website, so
  # the same edit from the app cannot write straight to the record either.
  test "a cluster incharge training edit goes for approval instead of saving" do
    cluster_incharge
    agronomist
    record = training_record
    record.update!(data: record.data.merge("created_by_id" => cluster_incharge.id.to_s))

    patch "/api/v1/farmer-trainings/#{record.id}", params: { male_count: "9" },
      headers: { "Authorization" => "Bearer #{login_token('edit_api_cc')}" }, as: :json

    assert_response :accepted
    body = response.parsed_body
    assert_equal true, body["pending_approval"]
    assert_equal "7", record.reload.data["male_count"],
      "the live record must not change before the Agronomist approves"

    revision = ModuleRecord.find(body["approval_request_id"])
    assert_equal TrainingEditApproval::SLUG, revision.module_slug
    assert_equal "Pending", revision.data["status"]
    assert_equal "9", revision.data.dig("proposed", "male_count"), "the edit is held on the request"
    assert_equal ["Agro Nomist"], revision.data["approvers"]
  end

  # Without an Agronomist on the office there is nobody to approve, and the web
  # refuses the edit rather than letting it through unreviewed.
  test "a cluster incharge edit is refused when no Agronomist is mapped" do
    cluster_incharge
    record = training_record
    record.update!(data: record.data.merge("created_by_id" => cluster_incharge.id.to_s))

    patch "/api/v1/farmer-trainings/#{record.id}", params: { male_count: "9" },
      headers: { "Authorization" => "Bearer #{login_token('edit_api_cc')}" }, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].join(" "), "Agronomist"
    assert_equal "7", record.reload.data["male_count"]
  end

  def cluster_incharge
    @cluster_incharge ||= User.create!(first_name: "Arti", last_name: "Shrama",
      user_name: "edit_api_cc", email: "edit_api_cc@example.com", mobile_no: "9876511301",
      password: "secret", user_type: "User", role: "Cluster Incharge", status: "Active",
      office_name: "FCO-C Sausar")
  end

  def agronomist
    @agronomist ||= User.create!(first_name: "Agro", last_name: "Nomist",
      user_name: "edit_api_agro", email: "edit_api_agro@example.com", mobile_no: "9876511302",
      password: "secret", user_type: "User", role: "Agronomist", status: "Active",
      office_name: "FCO-C Sausar")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def login_token(user_name)
    post api_v1_login_path, params: { login: user_name, password: "secret" }, as: :json
    assert_response :success
    response.parsed_body["token"]
  end

  def training_record
    @training_record ||= ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "July", "ics_block" => "ICS-1", "ics_name" => "ICS-1",
      "gram_name" => "Village 1", "village_name" => "Village 1", "fco_name" => "FCO-C Sausar",
      "trainer_name" => "Trainer", "trainer_contact" => "9876511000",
      "training_date" => "2026-07-10", "training_location" => "Hall A",
      "main_activity" => "Farmers' Training", "sub_activity" => "FFS",
      "training_method" => "FFS", "training_description" => "Demo",
      "male_count" => "7", "female_count" => "3", "total_farmer_count" => "10",
      "farmer_count" => "2", "selected_farmer_ids" => %w[1 2],
      "next_farmer_training_date" => "2026-08-10",
      "training_register_upload" => ["/uploads/module_records/register.pdf"],
      "photo_front_view" => ["/uploads/module_records/photo.jpg"],
      "created_by_id" => @admin.id.to_s
    })
  end

  def other_target_record
    @other_target_record ||= begin
      jj = vrp("Other JJ", "9876511101")
      target = TargetMapping.create!(vrp: jj, fco_id: "13", fco_name: "Betul-FCO",
        ics_id: "39", ics_name: "Athner", village_id: "3155", village_name: "Khairi",
        month_name: "October", main_activity_name: "Farmers WhatsApp Groups",
        activity_name: "Village level farmers groups", afl_ids: [], farmer_count: 0,
        target_quantity: 10, completion_date: Date.new(2026, 10, 31),
        created_by_type: "User", created_by_id: @admin.id)
      ModuleRecord.create!(module_slug: "add-activity-group", data: {
        "main_activity_name" => "Farmers WhatsApp Groups", "main_activity_type" => "Other",
        "status" => "Active"
      })
      ModuleRecord.create!(module_slug: "other-target", data: {
        "target_mapping_id" => target.id.to_s, "jeevika_jankar_id" => jj.id.to_s,
        "jeevika_jankar_name" => jj.name, "contact_number" => "9876511101",
        "month" => "October", "ics" => "Athner", "village" => "Khairi",
        "main_activity" => "Farmers WhatsApp Groups", "training_topic" => "Farmers WhatsApp Groups",
        "sub_activity" => "Village level farmers groups",
        "training_subject" => "Village level farmers groups",
        "completion_date" => "2026-10-31", "target" => "10", "achievement" => "5",
        "created_by_id" => @admin.id.to_s
      })
    end
  end

  def vrp(name, mobile)
    Vrp.create!(name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "ed#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      user_name: "ed_#{SecureRandom.hex(4)}", password: "secret", fcoc: "FCO-C Sausar")
  end
end
