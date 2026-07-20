require "test_helper"

class VrpAgreementsControllerTest < ActionDispatch::IntegrationTest
  test "accepted agreement list shows signed vrps" do
    vrp = create_vrp(
      user_name: "signed_vrp",
      password: "secret",
      agreement_accepted_at: Time.current,
      agreement_signature_data: "data:image/png;base64,signature"
    )
    create_vrp(
      user_name: "unsigned_vrp",
      password: "secret",
      agreement_accepted_at: Time.current
    )

    post login_path, params: { login: "signed_vrp", password: "secret" }
    follow_redirect!

    get vrp_agreements_path

    assert_response :success
    assert_includes response.body, "Accepted Agreement by Jeevika Jankar"
    assert_includes response.body, vrp.name
    refute_includes response.body, "unsigned_vrp"
  end

  test "accepted agreement detail page shows signature" do
    vrp = create_vrp(
      user_name: "detail_vrp",
      password: "secret",
      agreement_accepted_at: Time.current,
      agreement_signature_data: "data:image/png;base64,signature"
    )

    post login_path, params: { login: "detail_vrp", password: "secret" }
    follow_redirect!

    get vrp_agreement_record_path(vrp)

    assert_response :success
    assert_includes response.body, "Signed Agreement"
    assert_includes response.body, "data:image/png;base64,signature"
  end

  test "accepted agreement delete resets signature requirement" do
    vrp = create_vrp(
      user_name: "reset_agreement_vrp",
      password: "secret",
      agreement_accepted_at: Time.current,
      agreement_signature_data: "data:image/png;base64,signature"
    )

    post login_path, params: { login: "reset_agreement_vrp", password: "secret" }
    follow_redirect!

    delete reset_vrp_agreement_path(vrp)

    assert_redirected_to vrp_agreements_path
    assert_nil vrp.reload.agreement_accepted_at
    assert_nil vrp.agreement_signature_data

    delete logout_path
    post login_path, params: { login: "reset_agreement_vrp", password: "secret" }

    assert_redirected_to vrp_agreement_path
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
