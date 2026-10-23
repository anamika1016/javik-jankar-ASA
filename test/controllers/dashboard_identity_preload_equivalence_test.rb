require "test_helper"

# Batching the dashboard creator lookups replaces a per-record
# User.find_by(email:)/(mobile_no:) with one User.where(email: [...]) whose
# results are written into the same per-request cache. users.email and
# users.mobile_no carry no unique index and no uniqueness validation, so two
# accounts can share either value - and the identity picked from them decides
# which approval steps a record matches. These tests pin that batching resolves
# the same account the per-record lookup did.
class DashboardIdentityPreloadEquivalenceTest < ActiveSupport::TestCase
  def controller
    ModulesController.new.tap do |c|
      c.instance_variable_set(:@current_app_user, {
        "id" => 1, "username" => "equiv_admin", "user_type" => "admin"
      })
    end
  end

  def make_user(suffix, email:, mobile:, role:)
    User.create!(
      first_name: "Dup", last_name: suffix, user_name: "dup_#{suffix}",
      email: email, mobile_no: mobile, password: "secret",
      role: role, stakeholder: "ASA", stakeholder_role: role,
      user_type: "user", status: "Active"
    )
  end

  def make_vrp(email:, mobile:, created_by_id: nil)
    Vrp.create!(
      name: "Equiv JJ", father_husband_name: "T", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "551234567890", account_no: "5512345678", bank_name: "B",
      branch: "T", ifsc_code: "TEST0123456", address: "A",
      mobile_no: mobile, email: email, experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, user_name: "equiv_jj", password: "secret",
      created_by_type: "User", created_by_id: created_by_id, status: 30
    )
  end

  # Resolves the creator identity the way the code did before batching: each
  # lookup goes straight to the database for that one record.
  def identity_without_preload(vrp)
    controller.send(:vrp_creator_identities_for_dashboard, vrp)
  end

  # Resolves it the way it does now: the batch runs first and the per-record
  # lookups read the cache it filled.
  def identity_with_preload(vrp)
    c = controller
    c.send(:preload_dashboard_vrp_identity_records!, [vrp])
    c.send(:vrp_creator_identities_for_dashboard, vrp)
  end

  test "batched lookup resolves the same identities for a unique creator" do
    creator = make_user("unique", email: "uniq@example.com", mobile: "9811100001", role: "Agronomist")
    vrp = make_vrp(email: "uniq@example.com", mobile: "9811100001", created_by_id: creator.id)

    assert_equal identity_without_preload(vrp), identity_with_preload(vrp)
  end

  test "batched lookup resolves the same identity when two accounts share an email" do
    first = make_user("email_a", email: "shared@example.com", mobile: "9811100002", role: "Role A")
    second = make_user("email_b", email: "shared@example.com", mobile: "9811100003", role: "Role B")
    assert_operator first.id, :<, second.id

    vrp = make_vrp(email: "shared@example.com", mobile: "9811100099")

    assert_equal identity_without_preload(vrp), identity_with_preload(vrp),
      "two users share this email, and batching picked a different account than " \
      "the per-record lookup did - that changes which approval steps match"
  end

  test "batched lookup resolves the same identity when two accounts share a mobile number" do
    first = make_user("mob_a", email: "mob_a@example.com", mobile: "9811100004", role: "Role A")
    second = make_user("mob_b", email: "mob_b@example.com", mobile: "9811100004", role: "Role B")
    assert_operator first.id, :<, second.id

    vrp = make_vrp(email: "nobody@example.com", mobile: "9811100004")

    assert_equal identity_without_preload(vrp), identity_with_preload(vrp),
      "two users share this mobile number, and batching picked a different " \
      "account than the per-record lookup did"
  end

  test "batched lookup agrees when the creator has no matching account at all" do
    vrp = make_vrp(email: "missing@example.com", mobile: "9811100005", created_by_id: 999_999)

    assert_equal identity_without_preload(vrp), identity_with_preload(vrp)
  end

  test "repeating the batch for overlapping sets does not change the resolved identities" do
    creator = make_user("overlap", email: "ov@example.com", mobile: "9811100006", role: "Agronomist")
    vrp = make_vrp(email: "ov@example.com", mobile: "9811100006", created_by_id: creator.id)

    c = controller
    c.send(:preload_dashboard_vrp_identity_records!, [vrp])
    once = c.send(:vrp_creator_identities_for_dashboard, vrp)

    # The incremental guard must not let a second, overlapping batch leave the
    # cache half-seeded for records it decided to skip.
    c2 = controller
    c2.send(:preload_dashboard_vrp_identity_records!, [vrp])
    c2.send(:preload_dashboard_vrp_identity_records!, [vrp])
    twice = c2.send(:vrp_creator_identities_for_dashboard, vrp)

    assert_equal once, twice
  end
end
