require "test_helper"

class GloballyUniqueUsernameTest < ActiveSupport::TestCase
  test "user name cannot duplicate a jeevika jankar username" do
    create_vrp(user_name: "SharedLogin")
    user = build_user(user_name: " sharedlogin ")

    assert_not user.save
    assert_includes user.errors[:user_name], "has already been taken"
  end

  test "jeevika jankar username cannot duplicate a user username" do
    build_user(user_name: "ExistingUser").tap(&:save!)
    vrp = build_vrp(user_name: "existinguser")

    assert_not vrp.save
    assert_includes vrp.errors[:user_name], "has already been taken"
  end

  test "new-user module username participates in global uniqueness" do
    build_user(user_name: "LegacyLogin").tap(&:save!)
    record = ModuleRecord.new(module_slug: "new-user", data: { "user_name" => "legacylogin" })

    assert_not record.save
    assert_includes record.errors[:base], "User Name has already been taken"
  end

  private

  def build_user(user_name:)
    User.new(
      first_name: "Unique",
      last_name: "User",
      email: "unique_#{SecureRandom.hex(3)}@example.com",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      password: "secret",
      user_name: user_name,
      user_type: "user",
      status: "Active"
    )
  end

  def create_vrp(user_name:)
    build_vrp(user_name: user_name).tap(&:save!)
  end

  def build_vrp(user_name:)
    Vrp.new(
      name: "Unique JJ",
      father_husband_name: "Test Father",
      gender: :male,
      date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current,
      aadhar_no: SecureRandom.random_number(10**12).to_s.rjust(12, "0"),
      account_no: SecureRandom.random_number(10**10).to_s.rjust(10, "0"),
      bank_name: "Test Bank",
      branch: "Test Branch",
      ifsc_code: "TEST0123456",
      address: "Test Address",
      mobile_no: "9#{SecureRandom.random_number(10**9).to_s.rjust(9, "0")}",
      email: "jj_#{SecureRandom.hex(3)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      password: "secret",
      user_name: user_name
    )
  end
end
