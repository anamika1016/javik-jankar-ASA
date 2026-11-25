require "test_helper"

class Api::V1::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "api login returns token and user for valid vrp credentials" do
    vrp = create_vrp(user_name: "api_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { login: "api_vrp", password: "secret" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["token"].present?
    assert_equal vrp.id, body.dig("user", "id")
    assert_equal "Vrp", body.dig("user", "record_type")
    assert_equal "api_vrp", body.dig("user", "username")
  end

  test "api login projects vrp type labels and preserves label order" do
    type = VrpType.create!(type_name: "Payload Type", is_active: true, is_deleted: false)
    legacy_type = ModuleRecord.create!(module_slug: "add-vrp-type", data: {
      "vrp_type_name" => "Legacy Payload Type",
      "jeevika_jankar_type_name" => "Preferred Legacy Payload Type"
    })
    vrp = create_vrp(
      user_name: "payload_type_login",
      password: "secret",
      vrp_type_ids: [type.id, legacy_type.id],
      agreement_accepted_at: Time.current
    )

    queries = []
    callback = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.match?(/FROM "(?:vrp_types|module_records)"/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      post api_v1_login_path, params: { login: vrp.user_name, password: "secret" }, as: :json
    end

    assert_response :success
    assert_equal ["Payload Type", "Preferred Legacy Payload Type"], response.parsed_body.dig("user", "vrp_types")
    assert_equal 2, queries.size
  end

  test "api login accepts username alias" do
    create_vrp(user_name: "api_username_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { username: "api_username_vrp", password: "secret" }, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
  end

  test "jeevika jankar login only authenticates vrp and returns vrp type as role" do
    type = VrpType.create!(type_name: "Jeevika Mobilizer", is_active: true, is_deleted: false)
    vrp = create_vrp(
      user_name: "shared_android_login",
      password: "vrp-secret",
      vrp_type_ids: [type.id],
      stakeholder: "Wrong Stakeholder",
      stakeholder_role: "Manager_ICS",
      role: "Manager ics",
      agreement_accepted_at: Time.current
    )
    duplicate_user = build_admin_user(user_name: "shared_android_login", password: "user-secret")
    duplicate_user.save!(validate: false) # Simulates duplicate usernames already present in production data.

    post "/api/v1/jeevika-jankar-login",
      params: { login: "shared_android_login", password: "vrp-secret" },
      as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal vrp.id, body.dig("user", "id")
    assert_equal "Vrp", body.dig("user", "record_type")
    assert_equal "Jeevika Mobilizer", body.dig("user", "role")
    assert_equal ["Jeevika Mobilizer"], body.dig("user", "vrp_types")
    assert_nil body.dig("user", "stakeholder")
    assert_nil body.dig("user", "stakeholder_role")
  end

  test "api login rejects invalid credentials" do
    create_vrp(user_name: "api_bad_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { login: "api_bad_vrp", password: "wrong" }, as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
    assert_equal "Invalid username or password.", response.parsed_body["message"]
  end

  test "api login blocks vrp without agreement" do
    create_vrp(user_name: "api_unsigned_vrp", password: "secret")

    post api_v1_login_path, params: { login: "api_unsigned_vrp", password: "secret" }, as: :json

    assert_response :forbidden
    assert_equal false, response.parsed_body["success"]
    assert_equal "agreement_required", response.parsed_body["error"]
  end

  test "api me returns current user with bearer token" do
    vrp = create_vrp(user_name: "api_me_vrp", password: "secret", agreement_accepted_at: Time.current)

    post api_v1_login_path, params: { login: "api_me_vrp", password: "secret" }, as: :json
    token = response.parsed_body["token"]

    get api_v1_me_path, headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_equal vrp.id, response.parsed_body.dig("user", "id")
  end

  test "api token stops working immediately after JJ is deactivated" do
    vrp = create_vrp(user_name: "inactive_token_vrp", password: "secret", agreement_accepted_at: Time.current)
    token = ApiAuthToken.encode(vrp)
    vrp.update!(is_active: false)

    get api_v1_me_path, headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :unauthorized
    assert_equal "Unauthorized. Please login again.", response.parsed_body["message"]
  end

  test "api me rejects missing token" do
    get api_v1_me_path, as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
  end

  test "web login still works after api addition" do
    create_vrp(user_name: "web_still_works", password: "secret", agreement_accepted_at: Time.current)

    post login_path, params: { login: "web_still_works", password: "secret" }

    assert_redirected_to dashboard_path
  end

  test "agreement GET supports pre-login credentials and ASA terms" do
    vrp = create_vrp(user_name: "agreement_mobile", password: "secret")
    get "/api/v1/jeevika-jankar-agreement", params: { username: vrp.user_name, password: "secret" }
    assert_response :success
    agreement = response.parsed_body.fetch("agreement")
    assert_equal vrp.name, agreement["name"]
    assert_equal true, agreement["required"]
    assert_includes agreement["intro"], "Action For Social Advancement"
    assert_equal 7, agreement["terms"].size
  end

  test "agreement GET rejects incorrect credentials without exposing identity" do
    create_vrp(user_name: "agreement_private", password: "secret")
    get "/api/v1/jeevika-jankar-agreement", params: { username: "agreement_private", password: "wrong" }
    assert_response :unauthorized
    assert_nil response.parsed_body["agreement"]
  end

  test "agreement accepts signature before login and allows subsequent login" do
    vrp = create_vrp(user_name: "agreement_accept", password: "secret")
    signature = "data:image/png;base64,iVBORw0KGgo="
    post "/api/v1/jeevika-jankar-agreement",
      params: { username: vrp.user_name, password: "secret", signature_data: signature }, as: :json
    assert_response :success
    assert_equal vrp.id, ApiAuthToken.find_user(response.parsed_body["token"]).id
    assert_equal true, response.parsed_body.dig("agreement", "accepted")
    assert_equal signature, vrp.reload.agreement_signature_data
    assert vrp.agreement_accepted_at.present?

    post "/api/v1/jeevika-jankar-login", params: { username: vrp.user_name, password: "secret" }, as: :json
    assert_response :success

    post "/api/v1/jeevika-jankar-agreement",
      params: { username: vrp.user_name, password: "secret", signature_data: signature }, as: :json
    assert_response :conflict
  end

  test "agreement acceptance requires authentication and a signature" do
    vrp = create_vrp(user_name: "agreement_unsigned", password: "secret")
    post "/api/v1/jeevika-jankar-agreement", params: { signature_data: "data:image/png;base64,AAAA" }, as: :json
    assert_response :unauthorized

    post "/api/v1/jeevika-jankar-agreement", params: { username: vrp.user_name, password: "secret" }, as: :json
    assert_response :unprocessable_entity
    assert_nil vrp.reload.agreement_accepted_at
  end

  test "agreement accepts mobile signature formats as a real PNG data URI" do
    png = "\x89PNG\r\n\x1A\n".b + SecureRandom.random_bytes(120)
    canonical = "data:image/png;base64,#{Base64.strict_encode64(png)}"
    wrapped = Base64.encode64(png) # Android Base64.DEFAULT style line breaks
    {
      "raw base64, no prefix" => Base64.strict_encode64(png),
      "line breaks" => "data:image/png;base64,#{wrapped}",
      "plus sent as space" => canonical.tr("+", " "),
      "url-safe, unpadded" => Base64.urlsafe_encode64(png, padding: false),
      "image/jpg prefix" => "data:image/jpg;base64,#{Base64.strict_encode64(png)}",
      "percent-encoded" => ERB::Util.url_encode(canonical),
      "charset in prefix" => "data:image/png;charset=utf-8;base64,#{Base64.strict_encode64(png)}",
      "quoted, JSON-escaped" => "\"data:image\\/png;base64,#{wrapped.gsub("\n", "\\n")}\"",
      "octet-stream prefix" => "data:application/octet-stream;base64,#{Base64.strict_encode64(png)}"
    }.each_with_index do |(label, signature), index|
      vrp = create_vrp(user_name: "agreement_format_#{index}", password: "secret")
      post "/api/v1/jeevika-jankar-agreement",
        params: { username: vrp.user_name, password: "secret", signature_data: signature }, as: :json
      assert_response :success, label
      assert_equal canonical, vrp.reload.agreement_signature_data, label
    end
  end

  test "agreement rejects a signature that is not an image" do
    vrp = create_vrp(user_name: "agreement_not_image", password: "secret")
    ["hello world", Base64.strict_encode64("just some text"), "data:image/png;base64,%%%"].each do |signature|
      post "/api/v1/jeevika-jankar-agreement",
        params: { username: vrp.user_name, password: "secret", signature_data: signature }, as: :json
      assert_response :unprocessable_entity, signature
    end
    assert_nil vrp.reload.agreement_accepted_at
  end

  test "agreement accepts a signature uploaded as an image file, sent under another name, or as WEBP" do
    png = "\x89PNG\r\n\x1A\n".b + SecureRandom.random_bytes(80)
    webp = "RIFF".b + [90].pack("V") + "WEBPVP8 ".b + SecureRandom.random_bytes(80)

    file_vrp = create_vrp(user_name: "agreement_file", password: "secret")
    Tempfile.create(["signature", ".png"], binmode: true) do |file|
      file.write(png)
      file.rewind
      post "/api/v1/jeevika-jankar-agreement", params: {
        username: file_vrp.user_name, password: "secret",
        signature_data: Rack::Test::UploadedFile.new(file.path, "image/png", true)
      }
    end
    assert_response :success
    assert_equal "data:image/png;base64,#{Base64.strict_encode64(png)}", file_vrp.reload.agreement_signature_data

    key_vrp = create_vrp(user_name: "agreement_key", password: "secret")
    post "/api/v1/jeevika-jankar-agreement",
      params: { username: key_vrp.user_name, password: "secret", signature_image: Base64.strict_encode64(png) }, as: :json
    assert_response :success

    webp_vrp = create_vrp(user_name: "agreement_webp", password: "secret")
    post "/api/v1/jeevika-jankar-agreement",
      params: { username: webp_vrp.user_name, password: "secret", signature_data: Base64.strict_encode64(webp) }, as: :json
    assert_response :success
    assert_equal "data:image/webp;base64,#{Base64.strict_encode64(webp)}", webp_vrp.reload.agreement_signature_data
  end

  test "agreement accepts the Android app's SVG signature and rejects unsafe SVG" do
    drawing = '<svg xmlns="http://www.w3.org/2000/svg" width="219.79" height="127.52" viewBox="0 0 219.79 127.52">' \
              '<path d="M 46.03 14 L 44.84 47.69 L 48.77 96.83" stroke="black" stroke-width="3" fill="none"/></svg>'
    sent = "data:image/svg+xml;base64,#{Base64.strict_encode64(drawing)}"

    vrp = create_vrp(user_name: "agreement_svg", password: "secret")
    # The app sends credentials in the query string and the drawing as "signature".
    post "/api/v1/jeevika-jankar-agreement?username=#{vrp.user_name}&password=secret", params: { signature: sent }, as: :json
    assert_response :success
    assert_equal sent, vrp.reload.agreement_signature_data

    plain = create_vrp(user_name: "agreement_svg_text", password: "secret")
    post "/api/v1/jeevika-jankar-agreement", params: { username: plain.user_name, password: "secret", signature: drawing }, as: :json
    assert_response :success

    unsafe = [
      drawing.sub("</svg>", "<script>alert(1)</script></svg>"),
      drawing.sub("<svg ", '<svg onload="alert(1)" '),
      drawing.sub("<path ", '<a href="https://example.com"><path ').sub("/></svg>", "/></a></svg>"),
      drawing.sub("<path ", "<image href=\"x.png\"/><path "),
      '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
      "<?xml version=\"1.0\"?><!DOCTYPE svg [<!ENTITY x \"y\">]>#{drawing}"
    ]
    rejected = create_vrp(user_name: "agreement_svg_bad", password: "secret")
    unsafe.each do |svg|
      post "/api/v1/jeevika-jankar-agreement",
        params: { username: rejected.user_name, password: "secret", signature: "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}" }, as: :json
      assert_response :unprocessable_entity, svg
    end
    assert_nil rejected.reload.agreement_accepted_at
  end

  test "agreement says whether the signature was missing or unreadable" do
    vrp = create_vrp(user_name: "agreement_errors", password: "secret")
    post "/api/v1/jeevika-jankar-agreement", params: { username: vrp.user_name, password: "secret" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "signature_missing", response.parsed_body["error_code"]
    assert_match "A valid digital signature is required.", response.parsed_body["message"]

    post "/api/v1/jeevika-jankar-agreement",
      params: { username: vrp.user_name, password: "secret", signature_data: "hello" }, as: :json
    assert_equal "signature_unreadable", response.parsed_body["error_code"]
    assert_nil vrp.reload.agreement_accepted_at
  end

  test "agreement supports bearer authentication and public terms" do
    get "/api/v1/jeevika-jankar-agreement"
    assert_response :success
    assert_equal "-", response.parsed_body.dig("agreement", "name")

    vrp = create_vrp(user_name: "agreement_bearer", password: "secret")
    post "/api/v1/jeevika-jankar-agreement",
      params: { signature_data: "data:image/png;base64,AAAA" },
      headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(vrp)}" }, as: :json
    assert_response :success
    assert vrp.reload.agreement_accepted?
  end

  private

  def create_vrp(attributes = {})
    defaults = {
      name: "Test VRP",
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
      email: "vrp#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      is_active: true,
      is_deleted: false
    }

    Vrp.create!(defaults.merge(attributes))
  end
  def build_admin_user(attributes = {})
    defaults = {
      first_name: "Duplicate",
      last_name: "User",
      email: "duplicate_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "8#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_type: "admin",
      status: "Active",
      stakeholder: "PAPL",
      role: "Manager ics"
    }
    User.new(defaults.merge(attributes))
  end
end
