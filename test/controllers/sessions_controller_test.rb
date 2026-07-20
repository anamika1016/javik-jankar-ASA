require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "vrp must accept agreement on first login" do
    village = ModuleRecord.create!(
      module_slug: "village-master",
      data: { "village_name" => "Test Village", "status" => "Active" }
    )
    vrp = create_vrp(user_name: "first_vrp", password: "secret", village_ids: [village.id.to_s])

    post login_path, params: { login: "first_vrp", password: "secret" }

    assert_redirected_to vrp_agreement_path
    assert_nil vrp.reload.agreement_accepted_at

    get vrp_agreement_path
    assert_response :success
    assert_includes response.body, "Name"
    assert_includes response.body, "Test Village"
    assert_includes response.body, "Mobile Number"
    assert_includes response.body, "Digital Signature"

    post vrp_agreement_path, params: { decision: "agree" }

    assert_response :unprocessable_entity
    assert_includes response.body, "Please sign before accepting the declaration."
    assert_nil vrp.reload.agreement_accepted_at

    post vrp_agreement_path, params: { decision: "agree", signature_data: "data:image/png;base64,signature" }

    assert_redirected_to dashboard_path
    assert vrp.reload.agreement_accepted_at.present?
    assert vrp.reload.agreement_signature_data.present?
  end

  test "vrp login remains blocked when agreement is declined" do
    vrp = create_vrp(user_name: "decline_vrp", password: "secret")

    post login_path, params: { login: "decline_vrp", password: "secret" }
    post vrp_agreement_path, params: { decision: "decline" }

    assert_redirected_to login_path
    assert_nil vrp.reload.agreement_accepted_at
  end

  test "vrp with accepted agreement logs in directly" do
    create_vrp(user_name: "accepted_vrp", password: "secret", agreement_accepted_at: Time.current)

    post login_path, params: { login: "accepted_vrp", password: "secret" }

    assert_redirected_to dashboard_path
  end

  test "invalid credentials redirect back to login with friendly error" do
    create_vrp(user_name: "wrong_password_vrp", password: "secret", agreement_accepted_at: Time.current)

    post login_path, params: { login: "wrong_password_vrp", password: "bad-secret" }

    assert_redirected_to login_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Invalid username or password."
  end

  test "forgot password otp api returns json success" do
    create_vrp(user_name: "otp_vrp", password: "secret", agreement_accepted_at: Time.current)
    sender = Minitest::Mock.new
    sender.expect(:deliver, OtpSmsSender::Result.new(success: true, message: "Gateway accepted OTP request."))

    OtpSmsSender.stub(:new, sender) do
      post send_forgot_password_otp_path, params: { username: "otp_vrp" }, as: :json
    end

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_equal "OTP sent to registered mobile number.", response.parsed_body["message"]
    sender.verify
  end

  test "forgot password otp api returns json failure when sms gateway fails" do
    create_vrp(user_name: "gateway_fail_vrp", password: "secret", agreement_accepted_at: Time.current)
    sender = Minitest::Mock.new
    sender.expect(
      :deliver,
      OtpSmsSender::Result.new(success: false, message: "Net::ReadTimeout: timed out")
    )

    OtpSmsSender.stub(:new, sender) do
      post send_forgot_password_otp_path, params: { username: "gateway_fail_vrp" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["success"]
    assert_equal "OTP could not be sent. Net::ReadTimeout: timed out. Please try again.", response.parsed_body["message"]
    assert_equal "Net::ReadTimeout: timed out", response.parsed_body.dig("sms", "message")
    sender.verify
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
end
