require "test_helper"
require_relative "../support/farmer_api_stubs"

# End to end over the real routes and controller: does an Android login
# actually produce a row on the Farmer App Logins page?
#
# The register call and the SMS gateway are the only things replaced -- no
# real text message is sent and no farmer's data is fetched.
class FarmerAppLoginFlowTest < ActionDispatch::IntegrationTest
  include FarmerApiStubs

  REGISTER_FARMER = {
    "id" => 5,
    "full_name" => "Pooja",
    "father_husband_name" => "Jay",
    "mobile_no" => "7898071513",
    "aadhaar_no" => "111122223333",
    "gender" => "Female",
    "age" => 28,
    "tracenet_id" => "MP2001415600",
    "ics_team_name" => "Ma Machna Crop Producer Company Ltd",
    "land_details" => [{ "id" => 2, "state_id" => 1, "district_id" => 36, "village_id" => 10143 }]
  }.freeze

  test "a farmer logging in by mobile appears in the web list" do
    assert_equal 0, FarmerAppLogin.count

    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send",
        params: { mobile_no: "7898071513" }.to_json,
        headers: json_headers

      assert_response :ok
      assert json_body["success"]
      assert_equal "******1513", json_body["mobile_masked"]
      token = json_body["otp_token"]
      assert_equal 1, sent_otps.size, "exactly one OTP should have gone to the gateway"

      post "/api/v1/farmer/login/otp/verify",
        params: { otp_token: token, otp: sent_otps.last }.to_json,
        headers: json_headers.merge("X-Device-Name" => "Redmi Note 12", "X-App-Version" => "1.0.3")

      assert_response :ok
      assert json_body["success"]
      assert json_body["token"].present?
      assert_equal "Pooja", json_body.dig("farmer", "full_name")
    end

    assert_equal 1, FarmerAppLogin.count
    login = FarmerAppLogin.first
    assert_equal "Pooja", login.full_name
    assert_equal "7898071513", login.mobile_no
    assert_equal "mobile", login.last_identifier_type
    assert_equal 1, login.login_count
    assert_equal "Redmi Note 12", login.last_device
    assert_equal "1.0.3", login.last_app_version
    assert login.last_logged_in_at.present?
  end

  test "logging in twice records the same farmer once, not twice" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      2.times do |attempt|
        identifier = attempt.zero? ? { mobile_no: "7898071513" } : { aadhaar_no: "111122223333" }

        # Past the resend throttle, so the second login is a real second OTP.
        travel_to(Time.current + (attempt * 2).minutes) do
          post "/api/v1/farmer/login/otp/send", params: identifier.to_json, headers: json_headers
          assert_response :ok

          post "/api/v1/farmer/login/otp/verify",
            params: { otp_token: json_body["otp_token"], otp: sent_otps.last }.to_json,
            headers: json_headers
          assert_response :ok
        end
      end
    end

    assert_equal 1, FarmerAppLogin.count
    assert_equal 2, FarmerAppLogin.first.login_count
  end

  test "an invalid mobile number never reaches the register" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps, register_calls|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "5898071513" }.to_json, headers: json_headers

      assert_response :unprocessable_entity
      assert_equal FarmerAppLogin::INVALID_MOBILE_MESSAGE, json_body["message"]
      assert_empty register_calls
      assert_empty sent_otps
    end

    assert_equal 0, FarmerAppLogin.count
  end

  test "a second OTP for the same mobile inside a minute is refused" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      2.times do
        post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      end

      assert_response :too_many_requests
      assert_equal 1, sent_otps.size, "the throttled request must not have sent a second text"
    end
  end

  test "a used OTP cannot be exchanged for a second session" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      token = json_body["otp_token"]

      2.times do
        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: token, otp: sent_otps.last }.to_json, headers: json_headers
      end

      assert_response :unauthorized
      assert_equal "This OTP has already been used. Please request a new one.", json_body["message"]
    end

    assert_equal 1, FarmerAppLogin.count, "the replay must not have logged a second time"
  end

  test "more than three wrong OTPs locks the mobile for an hour, then it opens again" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      token = json_body["otp_token"]

      # Three wrong guesses are allowed and counted.
      3.times do
        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: token, otp: "000000" }.to_json, headers: json_headers
        assert_response :unauthorized
      end
      assert_equal 3, FarmerLoginLock.for_mobile("7898071513").failed_attempts

      # The fourth takes it past the limit.
      post "/api/v1/farmer/login/otp/verify",
        params: { otp_token: token, otp: "000000" }.to_json, headers: json_headers
      assert_response :locked
      assert_match(/locked for/, json_body["message"])

      # Locked means locked: a fresh OTP cannot be requested either.
      travel_to(FarmerLoginOtp::RESEND_INTERVAL.from_now + 1.second) do
        post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
        assert_response :locked
      end

      # An hour later the farmer can log in normally again.
      travel_to(FarmerLoginLock::LOCK_DURATION.from_now + 1.minute) do
        post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
        assert_response :ok

        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: json_body["otp_token"], otp: sent_otps.last }.to_json, headers: json_headers
        assert_response :ok
      end
    end

    assert_equal 1, FarmerAppLogin.count
    # A successful login clears the record of past wrong guesses.
    assert_equal 0, FarmerLoginLock.for_mobile("7898071513").failed_attempts
  end

  test "requesting a fresh OTP does not buy three more guesses" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do
      4.times do |round|
        travel_to(Time.current + (round * 70).seconds) do
          post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
          break unless response.successful?

          post "/api/v1/farmer/login/otp/verify",
            params: { otp_token: json_body["otp_token"], otp: "000000" }.to_json, headers: json_headers
        end
      end

      assert_response :locked
    end
  end

  test "an OTP dies two minutes after it was sent" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      assert_equal 120, FarmerLoginOtp::TTL.to_i

      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      assert_equal 120, json_body["expires_in_seconds"]
      token = json_body["otp_token"]

      travel_to(Time.current + 2.minutes + 1.second) do
        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: token, otp: sent_otps.last }.to_json, headers: json_headers
      end

      assert_response :unauthorized
      assert_equal "OTP has expired. Please request a new one.", json_body["message"]
    end

    assert_equal 0, FarmerAppLogin.count
  end

  test "resend issues a new OTP and retires the previous one" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      first_token = json_body["otp_token"]
      first_otp = sent_otps.last

      travel_to(FarmerLoginOtp::RESEND_INTERVAL.from_now + 1.second) do
        # Resend needs only the token the app already holds.
        post "/api/v1/farmer/login/otp/resend", params: { otp_token: first_token }.to_json, headers: json_headers
        assert_response :ok
        assert_equal 2, sent_otps.size
        second_token = json_body["otp_token"]

        # The superseded code must no longer work.
        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: first_token, otp: first_otp }.to_json, headers: json_headers
        assert_response :unauthorized

        post "/api/v1/farmer/login/otp/verify",
          params: { otp_token: second_token, otp: sent_otps.last }.to_json, headers: json_headers
        assert_response :ok
      end
    end

    assert_equal 1, FarmerAppLogin.count
  end

  test "the login records where it came from" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      post "/api/v1/farmer/login/otp/verify",
        params: { otp_token: json_body["otp_token"], otp: sent_otps.last }.to_json,
        headers: json_headers.merge(
          "X-Latitude" => "23.2250491", "X-Longitude" => "74.8512613",
          "X-Location" => "Bhawanipatna, Odisha", "X-Device-Name" => "Redmi Note 12"
        )
      assert_response :ok
    end

    login = FarmerAppLogin.first
    assert_in_delta 23.2250491, login.last_login_latitude.to_f, 0.0000001
    assert_in_delta 74.8512613, login.last_login_longitude.to_f, 0.0000001
    assert_equal "Bhawanipatna, Odisha", login.last_login_place
    assert login.last_login_ip.present?
  end

  test "a nonsense coordinate from the app is dropped, not stored" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      post "/api/v1/farmer/login/otp/verify",
        params: { otp_token: json_body["otp_token"], otp: sent_otps.last }.to_json,
        headers: json_headers.merge("X-Latitude" => "not-a-number", "X-Longitude" => "999")
      assert_response :ok
    end

    login = FarmerAppLogin.first
    assert_nil login.last_login_latitude
    assert_equal 180, login.last_login_longitude.to_i
  end

  test "the farmer token opens the farmer profile and nothing else" do
    stub_farmer_apis(farmer: REGISTER_FARMER) do |sent_otps|
      post "/api/v1/farmer/login/otp/send", params: { mobile_no: "7898071513" }.to_json, headers: json_headers
      post "/api/v1/farmer/login/otp/verify",
        params: { otp_token: json_body["otp_token"], otp: sent_otps.last }.to_json, headers: json_headers
      token = json_body["token"]

      get "/api/v1/farmer/me", headers: { "Authorization" => "Bearer #{token}" }
      assert_response :ok
      assert_equal "Pooja", json_body.dig("farmer", "full_name")

      # The same token must be worthless on a staff endpoint.
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
      assert_response :unauthorized
    end
  end

  private

  def json_headers
    { "Content-Type" => "application/json" }
  end

  def json_body
    JSON.parse(response.body)
  end
end
