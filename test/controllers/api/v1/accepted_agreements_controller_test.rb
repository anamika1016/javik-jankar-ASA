require "test_helper"

class Api::V1::AcceptedAgreementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = SecureRandom.hex(4)
    @admin = User.create!(user_name: "agr_api_admin_#{@tag}", password: "secret", first_name: "Adm",
                          user_type: "admin", status: "Active")
    @signed = jj("Signed JJ #{@tag}", "9876511#{rand(100..999)}", accepted: true)
    @other = jj("Other JJ #{@tag}", "9876522#{rand(100..999)}", accepted: true)
    @unsigned = jj("Unsigned JJ #{@tag}", "9876533#{rand(100..999)}", accepted: false)
  end

  def jj(name, mobile, accepted:)
    Vrp.create!(
      name: name, father_husband_name: "F", gender: :male, date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current, aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "agr#{SecureRandom.hex(4)}@example.com", experience_in_years: 1, office_detail_id: 0,
      to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", user_name: "agr_#{SecureRandom.hex(4)}",
      fcoc: "FCO-Agr#{@tag}", to_name: "TO-Agr#{@tag}",
      agreement_accepted_at: (Time.current if accepted),
      agreement_signature_data: ("data:image/png;base64,iVBORw0KGgo=" if accepted)
    )
  end

  def auth(user)
    { "Authorization" => "Bearer #{ApiAuthToken.encode(user)}" }
  end

  test "needs a login" do
    get "/api/v1/accepted-agreements"
    assert_response :unauthorized
  end

  test "admin gets the accepted agreements with the page's columns, searchable" do
    get "/api/v1/accepted-agreements", params: { q: @tag, per_page: 50 }, headers: auth(@admin)
    assert_response :success
    body = response.parsed_body
    names = body["accepted_agreements"].map { |row| row["name"] }
    assert_includes names, @signed.name
    assert_includes names, @other.name
    assert_not_includes names, @unsigned.name

    row = body["accepted_agreements"].find { |item| item["id"] == @signed.id }
    assert_equal "FCO-Agr#{@tag}", row["fco_name"]
    assert_equal "TO-Agr#{@tag}", row["to_name"]
    assert_equal @signed.mobile_no, row["mobile_number"]
    assert_equal "Signed", row["signature"]
    assert row.key?("village")
    assert_nil row["signature_data"], "the list must not carry the signature image"

    get "/api/v1/accepted-agreements", params: { q: @signed.mobile_no }, headers: auth(@admin)
    assert_equal [@signed.id], response.parsed_body["accepted_agreements"].map { |item| item["id"] }

    get "/api/v1/accepted-agreements", params: { q: @tag, per_page: 1, page: 2 }, headers: auth(@admin)
    assert_equal 1, response.parsed_body["count"]
    assert_equal 2, response.parsed_body["total_count"]
  end

  test "a Jeevika Jankar sees only their own agreement" do
    get "/api/v1/accepted-agreements", headers: auth(@signed)
    assert_response :success
    assert_equal [@signed.id], response.parsed_body["accepted_agreements"].map { |item| item["id"] }

    get "/api/v1/accepted-agreements/#{@other.id}", headers: auth(@signed)
    assert_response :not_found
  end

  test "detail returns the signature and agreement text" do
    get "/api/v1/accepted-agreements/#{@signed.id}", headers: auth(@admin)
    assert_response :success
    detail = response.parsed_body["accepted_agreement"]
    assert_equal @signed.agreement_signature_data, detail["signature_data"]
    assert_equal "TO-Agr#{@tag}", detail["to_name"]
    assert detail["agreement"]["terms"].any?

    get "/api/v1/accepted-agreements/#{@unsigned.id}", headers: auth(@admin)
    assert_response :not_found
  end

  test "an FCO office user sees the agreements of that office's Jeevika Jankars only" do
    elsewhere = jj("Elsewhere JJ #{@tag}", "9876544#{rand(100..999)}", accepted: true)
    elsewhere.update!(fcoc: "FCO-Far#{@tag}")
    staff = User.create!(user_name: "agr_fco_#{@tag}", password: "secret", first_name: "Fco", last_name: "Staff",
                         user_type: "user", status: "Active", office_name: "FCO-Agr#{@tag}", role: "FCO")

    get "/api/v1/accepted-agreements", params: { per_page: 1000 }, headers: auth(staff)
    assert_response :success
    ids = response.parsed_body["accepted_agreements"].map { |item| item["id"] }
    assert_includes ids, @signed.id
    assert_not_includes ids, elsewhere.id
  end
end
