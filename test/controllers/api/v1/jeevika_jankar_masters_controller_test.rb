require "test_helper"

class Api::V1::JeevikaJankarMastersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      first_name: "Master", last_name: "Admin", email: "master_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}", password: "secret",
      user_name: "master_#{SecureRandom.hex(3)}", user_type: "admin", status: "Active",
      stakeholder: "PAPL", role: "Admin"
    )
    post api_v1_login_path, params: { login: @user.user_name, password: "secret" }, as: :json
    @headers = { "Authorization" => "Bearer #{response.parsed_body['token']}" }
  end

  test "master APIs require authentication" do
    get "/api/v1/jeevika-jankar-masters/states", as: :json
    assert_response :unauthorized
  end

  test "state list returns active records" do
    active = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Bihar", "state_code" => "10", "status" => "Active" })
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Hidden", "status" => "Inactive" })

    get "/api/v1/jeevika-jankar-masters/states", headers: @headers, as: :json

    assert_response :success
    assert_equal [ active.id ], response.parsed_body["states"].map { |row| row["id"] }
  end

  test "district list supports state filter" do
    ModuleRecord.create!(module_slug: "district-master", data: { "state" => "Bihar", "district_name" => "Patna", "status" => "Active" })
    ModuleRecord.create!(module_slug: "district-master", data: { "state" => "Jharkhand", "district_name" => "Ranchi", "status" => "Active" })

    get "/api/v1/jeevika-jankar-masters/districts", params: { state: "Bihar" }, headers: @headers, as: :json

    assert_response :success
    assert_equal [ "Patna" ], response.parsed_body["districts"].map { |row| row["district_name"] }
  end

  test "large village lookup stays on a bounded SQL path" do
    40.times do |index|
      ModuleRecord.create!(module_slug: "village-master", data: {
        "state" => "Madhya Pradesh", "district" => "Chhindwara", "block" => "Sausar",
        "gram_panchayat" => "GP #{index}", "village_name" => "Village #{index}",
        "village_code" => index.to_s, "status" => "Active"
      })
    end
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT")
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/api/v1/jeevika-jankar-masters/villages",
        params: { state: "Madhya Pradesh", district: "Chhindwara", block: "Sausar" },
        headers: @headers, as: :json
    end

    assert_response :success
    assert_equal 40, response.parsed_body["count"]
    assert_operator queries.size, :<=, 4, "master list must filter in SQL without per-row queries"
  end

  test "mobile location master endpoints return their configured collections" do
    ModuleRecord.create!(module_slug: "gram-panchayat-master", data: {
      "state" => "Bihar", "district" => "Patna", "block" => "Bihta",
      "gram_panchayat_name" => "Amhara", "gp_code" => "GP1", "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "village-master", data: {
      "state" => "Bihar", "district" => "Patna", "block" => "Bihta",
      "gram_panchayat" => "Amhara", "village_name" => "Painal",
      "village_code" => "V1", "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "lg-directory-list", data: {
      "state_name" => "Bihar", "district_name" => "Patna", "block_name" => "Bihta",
      "gram_name" => "Amhara", "village_name" => "Painal"
    })

    {
      "gram-panchayats" => "gram_panchayats",
      "villages" => "villages",
      "all-list" => "all_list"
    }.each do |path, response_key|
      get "/api/v1/jeevika-jankar-masters/#{path}", headers: @headers, as: :json

      assert_response :success
      assert_equal true, response.parsed_body["success"]
      assert_equal 1, response.parsed_body[response_key].size
    end
  end

  test "creates jeevika jankar type without module web action" do
    assert_difference("ModuleRecord.where(module_slug: 'add-vrp-type').count", 1) do
      post "/api/v1/jeevika-jankar-types",
        params: { jeevika_jankar_type_name: "Community Mobilizer" }, headers: @headers, as: :json
    end

    assert_response :created
    assert_equal "Community Mobilizer", response.parsed_body.dig("jeevika_jankar_type", "jeevika_jankar_type_name")
  end

  test "type list supports legacy name and returns dropdown fields" do
    type = ModuleRecord.create!(
      module_slug: "add-vrp-type",
      data: { "vrp_type_name" => "Legacy Jankar Type", "status" => "Active" }
    )

    get "/api/v1/jeevika-jankar-types", headers: @headers, as: :json

    assert_response :success
    option = response.parsed_body.fetch("jeevika_jankar_types").find { |row| row["id"] == type.id }
    assert_equal "Legacy Jankar Type", option["jeevika_jankar_type_name"]
    assert_equal "Legacy Jankar Type", option["label"]
    assert_equal type.id, option["value"]
  end

  test "type list supports position type name field" do
    type = ModuleRecord.create!(
      module_slug: "add-vrp-type",
      data: { "position_type_name" => "Jeevika Position Type", "status" => "Active" }
    )

    get "/api/v1/jeevika-jankar-types", headers: @headers, as: :json

    option = response.parsed_body.fetch("jeevika_jankar_types").find { |row| row["id"] == type.id }
    assert_equal "Jeevika Position Type", option["label"]
  end

  test "cluster incharge endpoint returns dropdown collection" do
    cluster_user = User.create!(
      first_name: "Cluster", last_name: "Officer", user_name: "cluster_officer",
      password: "secret", role: "Cluster Incharge", status: "Active",
      office_category: "FCO", office: "Cluster Office"
    )

    get "/api/v1/jeevika-jankar-masters/cluster-incharges", headers: @headers, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    option = response.parsed_body["cluster_incharges"].find { |row| row["value"] == cluster_user.full_name }
    assert_equal "Cluster Officer (Cluster Incharge)", option["label"]
    assert_equal "FCO", option["office_category"]
  end
end
