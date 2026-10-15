require "test_helper"

# Endpoint wiring and access rules. These cover the paths that never reach the
# upstream server; the payload itself is covered by JjMappedFarmersApiTest,
# where the two external lookups are injected.
class Api::V1::JjMappedFarmersControllerTest < ActionDispatch::IntegrationTest
  test "every endpoint requires authentication" do
    %w[/api/v1/jj-mapped-farmers /api/v1/jj-mapped-farmers/jeevika-jankars
       /api/v1/jj-mapped-farmers/filters].each do |path|
      get path, as: :json
      assert_response :unauthorized, "#{path} answered without a token"
    end
  end

  test "the filter endpoint lists the months and years the screen offers" do
    body = get_json("/api/v1/jj-mapped-farmers/filters", admin)

    assert_equal true, body["success"]
    assert_equal 12, body["months"].size
    assert_equal({ "id" => "1", "name" => "January", "label" => "January (01)" }, body["months"].first)
    assert_equal %w[2024 2030], [body["years"].first, body["years"].last]
  end

  # The point of the Jeevika Jankar login: nothing to choose, nobody else.
  test "a Jeevika Jankar login has nothing to choose and is already selected" do
    body = get_json("/api/v1/jj-mapped-farmers/jeevika-jankars", ApiAuthToken.encode(mine))

    assert_equal "jeevika_jankar", body["login_type"]
    assert_equal false, body["can_choose_jeevika_jankar"]
    assert_empty body["jeevika_jankars"]
    assert_equal "9000000001", body["selected_mobile_no"]
  end

  test "a cluster incharge is offered only the Jeevika Jankars mapped to them" do
    mine
    theirs
    body = get_json("/api/v1/jj-mapped-farmers/jeevika-jankars", cluster_incharge)

    assert_equal "staff", body["login_type"]
    assert_equal true, body["can_choose_jeevika_jankar"]
    assert_equal ["9000000001"], body["jeevika_jankars"].map { |row| row["mobile_no"] }
    assert_equal "Sangeeta Uikey - 9000000001", body["jeevika_jankars"].first["label"]
    assert_equal "9000000001", body["selected_mobile_no"],
      "one Jeevika Jankar means nothing to choose, so it is loaded"
  end

  test "a cluster incharge asking for a Jeevika Jankar outside their cluster gets nothing" do
    mine
    theirs
    body = get_json("/api/v1/jj-mapped-farmers", cluster_incharge,
      mobile_no: "9000000002", month: "10", year: "2026")

    assert_nil body.dig("filters", "mobile_no"), "another cluster's Jeevika Jankar must not be loaded"
    assert_equal 0, body["count"]
    assert_empty body["farmers"]
    assert_equal ["9000000001"], body["jeevika_jankars"].map { |row| row["mobile_no"] }
  end

  test "a staff login with no Jeevika Jankar under them is given an empty screen" do
    theirs
    body = get_json("/api/v1/jj-mapped-farmers", cluster_incharge, month: "10", year: "2026")

    assert_empty body["jeevika_jankars"]
    assert_nil body["filters"]["mobile_no"]
    assert_equal 0, body["count"]
  end

  def get_json(path, token, params = {})
    get path, params: params, headers: { "Authorization" => "Bearer #{token}" }, as: :json
    assert_response :success
    response.parsed_body
  end

  def admin
    @admin ||= login("jjmf_admin", User.create!(first_name: "Jj", last_name: "Admin",
      user_name: "jjmf_admin", email: "jjmf_admin@example.com", mobile_no: "9876600001",
      password: "secret", user_type: "admin", status: "Active"))
  end

  def cluster_incharge
    @cluster_incharge ||= login("jjmf_cc", User.create!(first_name: "Arti", last_name: "Shrama",
      user_name: "jjmf_cc", email: "jjmf_cc@example.com", mobile_no: "9876600002",
      password: "secret", user_type: "User", role: "Cluster Incharge", status: "Active"))
  end

  def login(user_name, _user)
    post api_v1_login_path, params: { login: user_name, password: "secret" }, as: :json
    assert_response :success
    response.parsed_body["token"]
  end

  def mine
    @mine ||= vrp("Sangeeta Uikey", "9000000001", cluster_incharge: "Arti Shrama")
  end

  def theirs
    @theirs ||= vrp("Nilesh Nagwanshi", "9000000002", cluster_incharge: "Other CC")
  end

  def vrp(name, mobile, **extra)
    Vrp.create!({ name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "jc#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      status: 55, user_name: "jc_#{SecureRandom.hex(4)}", password: "secret" }.merge(extra))
  end
end
