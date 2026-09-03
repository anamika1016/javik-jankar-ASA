require "test_helper"

class VrpsControllerTest < ActionDispatch::IntegrationTest
  test "index includes both registered and mapped jeevika jankars for user login" do
    user = create_user(
      first_name: "Diwakar",
      last_name: "Tiwari",
      user_name: "diwakar_jj_list",
      email: "diwakar_jj_list@example.com"
    )

    own_vrp = create_vrp(name: "Registered JJ", user_name: "registered_jj", created_by_id: user.id)
    mapped_vrp = create_vrp(name: "Mapped JJ", user_name: "mapped_jj", cluster_incharge: "Diwakar Tiwari")
    hidden_vrp = create_vrp(name: "Hidden JJ", user_name: "hidden_jj")

    post login_path, params: { login: user.user_name, password: "secret" }
    get vrps_path

    assert_response :success
    assert_includes response.body, own_vrp.name
    assert_includes response.body, mapped_vrp.name
    assert_not_includes response.body, hidden_vrp.name
  end

  test "show falls back to saved gram panchayat and village lists when profile location is blank" do
    admin = create_admin_user(user_name: "vrp_show_admin", password: "secret")
    gram_panchayat = ModuleRecord.create!(
      module_slug: "gram-panchayat-master",
      data: {
        "state_name" => "Odisha",
        "district_name" => "Kalahandi",
        "block_name" => "Bhawanipatna",
        "gram_panchayat_name" => "Gobardhanpur",
        "status" => "Active"
      }
    )
    village = ModuleRecord.create!(
      module_slug: "village-master",
      data: {
        "state_name" => "Odisha",
        "district_name" => "Kalahandi",
        "block_name" => "Bhawanipatna",
        "gram_panchayat_name" => "Gobardhanpur",
        "village_name" => "Patavaler",
        "status" => "Active"
      }
    )
    vrp = create_vrp(
      user_name: "profile_blank_jj",
      created_by_id: admin.id,
      gram_panchayat_ids: [gram_panchayat.id.to_s],
      village_ids: [village.id.to_s]
    )

    post login_path, params: { login: "vrp_show_admin", password: "secret" }
    get vrp_path(vrp)

    assert_response :success
    assert_select ".table-shell.mt-4 tbody td", text: "Odisha"
    assert_select ".table-shell.mt-4 tbody td", text: "Kalahandi"
    assert_select ".table-shell.mt-4 tbody td", text: "Bhawanipatna"
    assert_select ".table-shell.mt-4 tbody td", text: "Gobardhanpur"
    assert_select ".table-shell.mt-4 tbody td", text: "Patavaler"
  end

  private

  def create_user(attributes = {})
    defaults = {
      first_name: "Regular",
      last_name: "User",
      email: "user_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "8#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_type: "user",
      status: "Active",
      stakeholder: "PAPL",
      role: "User"
    }
    User.create!(defaults.merge(attributes))
  end

  def create_admin_user(attributes = {})
    defaults = {
      first_name: "Web",
      last_name: "Admin",
      email: "vrp_show_admin_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_type: "admin",
      status: "Active",
      stakeholder: "PAPL",
      role: "Admin"
    }
    User.create!(defaults.merge(attributes))
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
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      is_active: true,
      is_deleted: false,
      password: "secret"
    }

    Vrp.create!(defaults.merge(attributes))
  end
end
