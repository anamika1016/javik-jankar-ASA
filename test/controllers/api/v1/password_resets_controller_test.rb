require "test_helper"

class Api::V1::PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  module SuccessfulSmsDeliver
    def deliver
      OtpSmsSender::Result.new(success: true, message: "Gateway accepted OTP request.")
    end
  end

  setup do
    OtpSmsSender.prepend(SuccessfulSmsDeliver) unless OtpSmsSender.ancestors.include?(SuccessfulSmsDeliver)
  end

  test "send forgot password otp for username" do
    create_vrp(user_name: "reset_vrp", password: "oldpass", mobile_no: "9988776633", agreement_accepted_at: Time.current)

    post "/api/v1/forgot-password/send-otp", params: { username: "reset_vrp" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["success"]
    assert body["reset_token"].present?
    assert_equal "******6633", body["mobile_masked"]
  end

  test "reset password with otp" do
    vrp = create_vrp(user_name: "reset_ok_vrp", password: "oldpass", mobile_no: "9988776644", agreement_accepted_at: Time.current)
    issued = ApiPasswordReset.issue(account: vrp, username: "reset_ok_vrp")

    post "/api/v1/forgot-password/reset",
      params: {
        username: "reset_ok_vrp",
        otp: issued[:otp],
        reset_token: issued[:reset_token],
        password: "newpass",
        confirmed_password: "newpass"
      },
      as: :json

    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_equal "newpass", vrp.reload.password
  end

  test "reset rejects wrong otp" do
    vrp = create_vrp(user_name: "reset_bad_vrp", password: "oldpass", mobile_no: "9988776655", agreement_accepted_at: Time.current)
    issued = ApiPasswordReset.issue(account: vrp, username: "reset_bad_vrp")

    post "/api/v1/forgot-password/reset",
      params: {
        username: "reset_bad_vrp",
        otp: "0000",
        reset_token: issued[:reset_token],
        password: "newpass",
        confirmed_password: "newpass"
      },
      as: :json

    assert_response :unauthorized
    assert_equal "oldpass", vrp.reload.password
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
