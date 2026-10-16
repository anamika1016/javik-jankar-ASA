require "test_helper"

class Api::V1::FarmerTargetApisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_admin_user(user_name: "api_farmer_admin", password: "secret")
    @token = api_login_token(login: "api_farmer_admin", password: "secret")
  end

  test "farmer training list requires auth" do
    get "/api/v1/farmer-trainings", as: :json
    assert_response :unauthorized
  end

  test "farmer training form data requires auth" do
    get "/api/v1/farmer-trainings/form-data", as: :json

    assert_response :unauthorized
  end

  test "farmer training farmer list requires auth" do
    get "/api/v1/farmer-trainings/farmers", as: :json

    assert_response :unauthorized
  end

  test "farmer training months require auth" do
    get "/api/v1/farmer-trainings/months", as: :json

    assert_response :unauthorized
  end

  test "mapped farmer list requires auth" do
    get "/api/v1/farmer-trainings/mapped-farmers", as: :json

    assert_response :unauthorized
  end

  test "farmer training list and form options work" do
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "July",
        "ics_block" => "ICS-1",
        "gram_name" => "Village 1",
        "trainer_name" => "Trainer",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/farmer-trainings", headers: auth_headers, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["farmer_trainings"].is_a?(Array)
    assert body["count"] >= 1

    get "/api/v1/farmer-trainings/form-options", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["options"].key?("target_mappings")
    assert response.parsed_body["options"].key?("autofill")
  end

  test "training forms alias works for React Native route names" do
    ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "July",
        "ics_block" => "ICS-1",
        "gram_name" => "Village 1",
        "trainer_name" => "Trainer",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/training-forms", headers: auth_headers, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["training_forms"].is_a?(Array)
    assert body["count"] >= 1

    get "/api/v1/training-forms/form-options", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["options"].key?("target_mappings")
    assert response.parsed_body["options"].key?("form_fields")
    assert response.parsed_body["options"].key?("people_options")

    get "/api/v1/training-forms/form-data", headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body.key?("form_fields")
    assert response.parsed_body.key?("autofill")
    assert response.parsed_body.key?("people_options")
  end

  test "training form list alias exposes saved training records" do
    record = ModuleRecord.create!(
      module_slug: "training-form",
      data: {
        "month" => "July",
        "ics_block" => "ICS-1",
        "gram_name" => "Village 1",
        "trainer_name" => "Trainer",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/training-form-list", headers: auth_headers, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["training_forms"].any? { |row| row["id"] == record.id }

    get "/api/v1/training-form-list/#{record.id}", headers: auth_headers, as: :json
    assert_response :success
    assert_equal record.id, response.parsed_body.dig("training_form", "id")
  end

  test "training form months include active month master rows without target mappings" do
    ModuleRecord.create!(module_slug: "month-master", data: { "month_name" => "August", "status" => "Active" })
    ModuleRecord.create!(module_slug: "month-master", data: { "month_name" => "September", "status" => "Active" })

    get "/api/v1/training-forms/months", headers: auth_headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal [ "August", "September" ], body["months"].map { |month| month["name"] }
    assert_equal 2, body["count"]
  end

  test "seed distribution list and form options work" do
    ModuleRecord.create!(
      module_slug: "seed-distribution-target",
      data: {
        "month" => "July",
        "ics" => "ICS-1",
        "village" => "Village 1",
        "jeevika_jankar_name" => "JJ One",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/seed-distribution-targets", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["seed_distribution_targets"].is_a?(Array)

    get "/api/v1/seed-distribution-targets/form-options", headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body["options"].key?("target_mappings")
    assert response.parsed_body["options"].key?("autofill")
  end

  test "papl360 list and form options work" do
    ModuleRecord.create!(
      module_slug: "papl360-target",
      data: {
        "month" => "July",
        "ics" => "ICS-1",
        "village" => "Village 1",
        "jeevika_jankar_name" => "JJ One",
        "created_by_id" => @user.id.to_s
      }
    )

    get "/api/v1/papl360-targets", headers: auth_headers, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert response.parsed_body["papl360_targets"].is_a?(Array)

    get "/api/v1/papl360-targets/form-options", headers: auth_headers, as: :json
    assert_response :success
  end

  test "other target form data create and list aliases work" do
    vrp = create_vrp(user_name: "other_target_vrp", name: "Other Target JJ", mobile_no: "9876543211")
    ModuleRecord.create!(
      module_slug: "add-activity-group",
      data: {
        "main_activity_name" => "Seed Distribution",
        "main_activity_type" => "Other",
        "status" => "Active"
      }
    )
    ModuleRecord.create!(
      module_slug: "add-vrp-activity",
      data: {
        "main_activity" => "Seed Distribution",
        "sub_activity_name" => "Packet Distribution",
        "status" => "Active"
      }
    )
    mapping = TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      month_name: "September",
      main_activity_name: "Seed Distribution",
      activity_name: "Packet Distribution",
      target_quantity: 10,
      afl_ids: []
    )

    get "/api/v1/other-targets/form-data", headers: auth_headers, as: :json
    assert_response :success
    form_data = response.parsed_body
    assert_equal true, form_data["success"]
    assert form_data["form_fields"].any? { |field| field["key"] == "achievement" }
    assert form_data["target_mappings"].any? { |row| row["target_mapping_id"] == mapping.id.to_s }
    assert_equal 5, form_data.dig("upload_constraints", "attachment_upload", "max_files")

    get "/api/v1/other-target-list/form-data",
      params: { month: "September", main_activity: "Seed Distribution" },
      headers: auth_headers,
      as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["count"]

    post "/api/v1/other-targets",
      params: {
        jeevika_jankar_name: "Other Target JJ",
        contact_number: "9876543211",
        department: "FCO One",
        month: "September",
        ics: "ICS One",
        village: "Village One",
        main_activity: "Seed Distribution",
        sub_activity: "Packet Distribution",
        completion_date: Date.current.to_s,
        achievement: "4"
      },
      headers: auth_headers,
      as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal mapping.id.to_s, body.dig("other_target", "data", "target_mapping_id")
    assert_equal "10", body.dig("other_target", "data", "target")
    assert_equal "4", body.dig("other_target", "data", "achievement")

    get "/api/v1/other-target-list", headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body["other_targets"].any? { |row| row.dig("data", "target_mapping_id") == mapping.id.to_s }
  end

  test "add farmer form list create and form options work" do
    vrp = create_vrp(user_name: "add_farmer_vrp", name: "Add Farmer VRP")
    mapping = TargetMapping.create!(
      vrp: vrp,
      fco_id: "FCO1",
      fco_name: "FCO One",
      ics_id: "ICS1",
      ics_name: "ICS One",
      village_id: "V1",
      village_name: "Village One",
      month_name: "July",
      main_activity_name: "New Farmer",
      activity_name: "Enrollment",
      target_quantity: 5,
      afl_ids: []
    )

    get "/api/v1/add-farmer-forms/form-options", headers: auth_headers, as: :json
    assert_response :success
    options = response.parsed_body["options"]
    assert options["mappings"].any? { |row| row["id"] == mapping.id.to_s }

    post "/api/v1/add-farmer-forms",
      params: {
        target_mapping_id: mapping.id.to_s,
        no_farmer: 3
      },
      headers: auth_headers,
      as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal true, body["success"]
    assert_equal "3", body.dig("add_farmer_form", "data", "no_farmer")
    assert_equal mapping.id.to_s, body.dig("add_farmer_form", "data", "target_mapping_id")

    get "/api/v1/add-farmer-forms", headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body["add_farmer_forms"].any?
  end

  test "web modules path still works after api addition" do
    post login_path, params: { login: "api_farmer_admin", password: "secret" }
    get "/modules/training-form-list"
    assert_response :success
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def api_login_token(login:, password:)
    post api_v1_login_path, params: { login: login, password: password }, as: :json
    assert_response :success
    response.parsed_body["token"]
  end

  def create_admin_user(attributes = {})
    defaults = {
      first_name: "Api",
      last_name: "Admin",
      email: "api_farmer_admin_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_type: "admin",
      status: "Active",
      stakeholder: "PAPL",
      role: "Admin"
    }
    User.create!(defaults.merge(attributes))
  end

  test "training list corrects stale total without confusing registered farmers and attendance" do
    record = ModuleRecord.create!(module_slug: "training-form", data: {
      "male_count" => "07", "female_count" => "3", "total_farmer_count" => "2",
      "farmer_count" => "99", "selected_farmer_ids" => ["1", "1", "2"]
    })
    get "/api/v1/farmer-trainings", headers: auth_headers, as: :json
    assert_response :success
    data = response.parsed_body["farmer_trainings"].find { |row| row["id"] == record.id }["data"]
    assert_equal "7", data["male_count"]
    assert_equal "3", data["female_count"]
    assert_equal "10", data["total_farmer_count"]
    assert_equal "2", data["farmer_count"]
    assert_equal "2", record.reload.data["total_farmer_count"], "read path must not rewrite saved forms"
  end

  test "mapped farmer loading batches queries and preserves completion and month filters" do
    vrp = create_vrp(fcoc: "FCO-C Test Office")
    farmer = Afl.create!(farmer_name: "Mapped", fco_id: "991", fco: "Test Office", ics_id: "ics-fast", ics_name: "ICS Fast", village_id: "v-fast", village_name: "Village Fast")
    30.times do |i|
      TargetMapping.create!(vrp: vrp, fco_id: "991", fco_name: "Test Office", ics_id: "ics-fast", ics_name: "ICS Fast", village_id: "v-fast", village_name: "Village Fast",
        month_name: "July", main_activity_name: "Training", activity_name: "Subject #{i}", target_quantity: 1, afl_ids: [farmer.id])
    end
    TargetMapping.create!(vrp: vrp, fco_id: "991", fco_name: "Test Office", ics_id: "ics-fast", ics_name: "ICS Fast", village_id: "v-fast", village_name: "Village Fast",
      month_name: "August", main_activity_name: "Training", activity_name: "Outside month", target_quantity: 1, afl_ids: [farmer.id])
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "July", "main_activity" => "Training", "sub_activity" => "Subject 0", "selected_farmer_ids" => [farmer.id.to_s] })
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] unless args.last[:cached] }, "sql.active_record") do
      get "/api/v1/farmer-trainings/mapped-farmers", params: { month: "July" }, headers: auth_headers, as: :json
    end
    assert_response :success
    body = response.parsed_body
    assert_equal 30, body["target_mapping_ids"].size
    assert_equal 1, body["count"]
    assert_equal 1, body["completed_count"]
    assert_equal 0, body["available_count"]
    assert_equal farmer.id.to_s, body["mapped_farmers"].first["id"]
    assert_operator queries.grep(/FROM "afls"/).size, :<=, 2, "AFL queries must not grow per target"
    assert_operator queries.grep(/FROM "vrps"/).size, :<=, 3, "JJ queries must not grow per target"
  end

  test "mapped farmers can use the location fallback without repeated AFL scans" do
    vrp = create_vrp(fcoc: "FCO-C Fallback")
    farmer = Afl.create!(farmer_name: "Fallback Farmer", fco_id: "993", fco: "Fallback", ics_id: "ics-f", ics_name: "ICS F", village_id: "v-f", village_name: "Village F")
    target = TargetMapping.create!(vrp: vrp, fco_id: "993", fco_name: "Fallback", ics_id: "ics-f", ics_name: "ICS F", village_id: "v-f", village_name: "Village F",
      month_name: "July", main_activity_name: "Training", activity_name: "Fallback Subject", target_quantity: 1, afl_ids: [])
    get "/api/v1/farmer-trainings/mapped-farmers", params: { month: "July" }, headers: auth_headers, as: :json
    assert_response :success
    assert_equal [target.id.to_s], response.parsed_body["target_mapping_ids"]
    assert_equal [farmer.id.to_s], response.parsed_body["mapped_farmers"].map { |row| row["id"] }
    assert_equal 1, response.parsed_body["available_count"]
  end

  test "mapped farmers remain available while editing their own training record" do
    vrp = create_vrp(fcoc: "FCO-C Edit")
    farmer = Afl.create!(farmer_name: "Saved Farmer", fco_id: "994", fco: "Edit",
      ics_id: "ics-edit", ics_name: "ICS Edit", village_id: "v-edit", village_name: "Village Edit")
    target = TargetMapping.create!(vrp: vrp, fco_id: "994", fco_name: "Edit",
      ics_id: "ics-edit", ics_name: "ICS Edit", village_id: "v-edit", village_name: "Village Edit",
      month_name: "July", main_activity_name: "Training", activity_name: "Edit Subject",
      target_quantity: 1, afl_ids: [farmer.id])
    record = ModuleRecord.create!(module_slug: "training-form", data: {
      "target_mapping_id" => target.id.to_s, "month" => "July", "main_activity" => "Training",
      "sub_activity" => "Edit Subject", "selected_farmer_ids" => [farmer.id.to_s]
    })

    get "/api/v1/farmer-trainings/mapped-farmers",
      params: { record_id: record.id, month: "July", main_activity: "Training", sub_activity: "Edit Subject" },
      headers: auth_headers, as: :json

    assert_response :success
    row = response.parsed_body["mapped_farmers"].find { |item| item["id"] == farmer.id.to_s }
    assert row
    assert_equal true, row["is_available"]
    assert_equal false, row["is_completed"]
  end

  def create_vrp(attributes = {})
    defaults = {
      name: "Test JJ",
      father_husband_name: "Test Father",
      gender: :male,
      date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current,
      aadhar_no: "123456789012",
      account_no: "1234567890",
      bank_name: "Test Bank",
      branch: "Test Branch",
      ifsc_code: "TEST0123456",
      address: "Test Address",
      mobile_no: "9876543210",
      email: "jj#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [ 1 ],
      gram_panchayat_ids: [ 1 ],
      village_ids: [ 1 ],
      is_active: true,
      is_deleted: false,
      status: 55,
      password: "secret"
    }

    Vrp.create!(defaults.merge(attributes))
  end
end
