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

  test "CC can deactivate a mapped Jeevika Jankar and audit is recorded" do
    cc = create_user(first_name: "Diwakar", last_name: "Tiwari", user_name: "mapped_cc_status")
    mapped_vrp = create_vrp(name: "Mapped Status JJ", cluster_incharge: "Diwakar Tiwari", is_active: true)
    hidden_vrp = create_vrp(name: "Other Status JJ", cluster_incharge: "Another CC", is_active: true)
    post login_path, params: { login: cc.user_name, password: "secret" }

    patch set_active_vrp_path(mapped_vrp), params: { active: false }

    assert_redirected_to vrps_path
    assert_not mapped_vrp.reload.is_active
    assert hidden_vrp.reload.is_active
    history = ModuleRecord.where(module_slug: "vrp-active-status-history").order(:id).last
    assert_equal mapped_vrp.id.to_s, history.data["vrp_id"]
    assert_equal "Diwakar Tiwari", history.data["action_by"]
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

  test "location options cascade through names with punctuation and multiple panchayats" do
    admin = create_admin_user(user_name: "location_admin", password: "secret")
    post login_path, params: { login: admin.user_name, password: "secret" }
    ["First GP", "Second GP"].each_with_index do |gp, index|
      ModuleRecord.create!(module_slug: "lg-directory-list", data: {
        "state_name" => " Test State ", "district_name" => "Test-District",
        "cd_block_name" => "Test Block", "gram_panchayat" => gp,
        "village_name" => "Test Village #{index}"
      })
    end
    filters = { state: "Test State", district: "Test-District", block: "Test Block",
                gram_panchayat: ["First GP", "Second GP"].to_json }
    { "district" => ["Test-District"], "block" => ["Test Block"],
      "gram-panchayat" => ["First GP", "Second GP"],
      "village" => ["Test Village 0", "Test Village 1"] }.each do |level, expected|
      get location_options_vrps_path, params: filters.merge(level: level)
      assert_response :success
      assert_equal expected, response.parsed_body.fetch("options").map { |option| option.fetch("value") }
    end
  end

  test "swapped imported panchayat codes and names expose every matching village" do
    admin = create_admin_user(user_name: "swapped_location_admin", password: "secret")
    post login_path, params: { login: admin.user_name, password: "secret" }
    base = { "state_name" => "MADHYA PRADESH", "district_name" => "Pandhurna",
             "cd_block_name" => "Pandhurna", "gram_panchayat" => "03658",
             "gp_code" => "Pandhurna", "status" => "Active" }
    3.times do |index|
      ModuleRecord.create!(module_slug: "lg-directory-list",
                           data: base.merge("village_name" => "Village #{index}"))
    end
    ModuleRecord.create!(module_slug: "lg-directory-list",
                         data: base.merge("cd_block_name" => "Sausar", "village_name" => "Other block village"))
    filters = { state: "MADHYA PRADESH", district: "Pandhurna", block: "Pandhurna" }
    get location_options_vrps_path, params: filters.merge(level: "gram-panchayat")
    assert_response :success
    assert_equal [{ "value" => "Pandhurna", "label" => "Pandhurna" }], response.parsed_body.fetch("options")

    get location_options_vrps_path, params: filters.merge(level: "village", gram_panchayat: ["Pandhurna"].to_json)
    assert_response :success
    assert_equal ["Village 0", "Village 1", "Village 2"], response.parsed_body.fetch("options").map { |option| option.fetch("value") }
  end

  test "location options include master-only villages and preserve distinct Hindi names" do
    admin = create_admin_user(user_name: "master_location_admin", password: "secret")
    post login_path, params: { login: admin.user_name, password: "secret" }
    base = { "state" => "Test State", "district" => "Test District", "block_name" => "Test Block",
             "gram_panchayat_name" => "Test GP", "status" => "Active" }
    ["गाँव एक", "गाँव दो"].each do |name|
      ModuleRecord.create!(module_slug: "village-master", data: base.merge("village_name" => name))
    end
    ModuleRecord.create!(module_slug: "village-master", data: base.merge("village_name" => "Inactive village", "status" => "Inactive"))
    ModuleRecord.create!(module_slug: "village-master", data: base.merge("village_name" => "Deleted village", "is_deleted" => true))
    filters = { state: "Test State", district: "Test District", block: "Test Block" }
    get location_options_vrps_path, params: filters.merge(level: "gram-panchayat")
    assert_response :success
    assert_equal ["Test GP"], response.parsed_body.fetch("options").map { |option| option.fetch("value") }
    get location_options_vrps_path, params: filters.merge(level: "village", gram_panchayat: "Test GP")
    assert_response :success
    assert_equal ["गाँव एक", "गाँव दो"].sort, response.parsed_body.fetch("options").map { |option| option.fetch("value") }.sort
  end

  test "active status change records actor date and appears in list" do
    admin = create_admin_user(user_name: "status_admin", first_name: "Status", last_name: "Admin", password: "secret")
    vrp = create_vrp(user_name: "status_jj", created_by_id: admin.id, is_active: true)
    post login_path, params: { login: admin.user_name, password: "secret" }

    patch set_active_vrp_path(vrp), params: { active: false }

    assert_redirected_to vrps_path
    assert_not vrp.reload.is_active
    history = ModuleRecord.where(module_slug: "vrp-active-status-history").order(:id).last
    assert_equal vrp.id.to_s, history.data["vrp_id"]
    assert_equal "Inactive", history.data["status"]
    assert_equal "Status Admin", history.data["action_by"]
    assert history.data["action_at"].present?

    get vrps_path
    assert_response :success
    assert_includes response.body, "Status Changed By"
    assert_includes response.body, "Status Admin"
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
