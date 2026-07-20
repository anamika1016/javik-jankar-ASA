require "test_helper"

class Api::V1::OtpLoginsControllerTest < ActionDispatch::IntegrationTest
  module SuccessfulSmsDeliver
    def deliver
      OtpSmsSender::Result.new(success: true, message: "Gateway accepted OTP request.")
    end
  end

  setup do
    OtpSmsSender.prepend(SuccessfulSmsDeliver) unless OtpSmsSender.ancestors.include?(SuccessfulSmsDeliver)
  end

  test "send otp for registered jeevika jankar mobile" do
    create_vrp(user_name: "otp_mobile_vrp", password: "secret", mobile_no: "9988776655", agreement_accepted_at: Time.current)

    post "/api/v1/login/otp/send", params: { mobile_no: "9988776655" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["otp_token"].present?
    assert_equal "******6655", body["mobile_masked"]
  end

  test "send otp rejects unknown mobile" do
    post "/api/v1/login/otp/send", params: { mobile_no: "9000000000" }, as: :json

    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["success"]
    assert_equal "Registered mobile number not found.", response.parsed_body["message"]
  end

  test "verify otp logs in jeevika jankar" do
    vrp = create_vrp(user_name: "otp_verify_vrp", password: "secret", mobile_no: "9988776611", agreement_accepted_at: Time.current)
    issued = ApiLoginOtp.issue(user: vrp, mobile: "9988776611")

    post "/api/v1/login/otp/verify",
      params: { mobile_no: "9988776611", otp: issued[:otp], otp_token: issued[:otp_token] },
      as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["token"].present?
    assert_equal vrp.id, body.dig("user", "id")
    assert_equal "Vrp", body.dig("user", "record_type")
  end

  test "verify otp rejects wrong code" do
    vrp = create_vrp(user_name: "otp_wrong_vrp", password: "secret", mobile_no: "9988776622", agreement_accepted_at: Time.current)
    issued = ApiLoginOtp.issue(user: vrp, mobile: "9988776622")

    post "/api/v1/login/otp/verify",
      params: { mobile_no: "9988776622", otp: "0000", otp_token: issued[:otp_token] },
      as: :json

    assert_response :unauthorized
    assert_equal false, response.parsed_body["success"]
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
