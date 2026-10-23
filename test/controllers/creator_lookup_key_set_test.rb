require "test_helper"

# Replacing index_by with a lowest-id rule was meant to change only which of
# several duplicate accounts wins. It must not change which keys the lookup
# holds: registered_by_user reads @preloaded_creator_users_by_email with
# vrp.email.to_s.strip.downcase and never checks that the email is present, so
# a blank key that index_by used to create still has to be there - otherwise a
# Jeevika Jankar with no email takes a different branch than it used to.
class CreatorLookupKeySetTest < ActiveSupport::TestCase
  class Probe
    include VrpAccess
    def current_app_user = nil
  end

  def make_user(suffix, email:, mobile: nil)
    User.create!(
      first_name: "Key", last_name: suffix, user_name: "key_#{suffix}",
      email: email, mobile_no: mobile, password: "secret",
      user_type: "user", status: "Active"
    )
  end

  def make_vrp(email:, created_by_id:)
    Vrp.create!(
      name: "Key JJ #{created_by_id}", father_husband_name: "T", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "77#{format('%010d', created_by_id)}", account_no: "7712345678",
      bank_name: "B", branch: "T", ifsc_code: "TEST0123456", address: "A",
      mobile_no: "9600000#{format('%03d', created_by_id % 1000)}", email: email,
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false,
      user_name: "key_jj_#{created_by_id}", password: "secret",
      created_by_type: "User", created_by_id: created_by_id, status: 10
    )
  end

  # What index_by produced before the change, for the same input.
  def index_by_reference(users)
    users.index_by { |user| user.email.to_s.strip.downcase }
  end

  test "the email lookup keeps the same keys index_by produced, blanks included" do
    blank_email_creator = make_user("blank", email: "")
    named_creator = make_user("named", email: "named@example.com")
    vrp_without_email = make_vrp(email: "", created_by_id: blank_email_creator.id)
    vrp_with_email = make_vrp(email: "named@example.com", created_by_id: named_creator.id)

    probe = Probe.new
    probe.send(:preload_vrp_creator_lookup_data!, [vrp_without_email, vrp_with_email])
    actual = probe.instance_variable_get(:@preloaded_creator_users_by_email)

    users = User.where(id: [blank_email_creator.id, named_creator.id]).to_a
    assert_equal index_by_reference(users).keys.sort, actual.keys.sort,
      "the key set changed, so a lookup that used to hit will now miss"
    assert actual.key?(""), "the blank email key index_by created must still exist"
  end

  test "among duplicate emails the lowest id wins and the key set is unchanged" do
    first = make_user("dup_first", email: "dup@example.com")
    second = make_user("dup_second", email: "dup@example.com")
    assert_operator first.id, :<, second.id
    vrp = make_vrp(email: "dup@example.com", created_by_id: first.id)

    probe = Probe.new
    probe.send(:preload_vrp_creator_lookup_data!, [vrp])
    actual = probe.instance_variable_get(:@preloaded_creator_users_by_email)

    users = User.where(id: [first.id, second.id]).to_a
    assert_equal index_by_reference(users).keys.sort, actual.keys.sort
    assert_equal first.id, actual["dup@example.com"].id,
      "find_by resolves the lowest id, so the batch has to agree"
  end

  test "identity lookup keeps blank-keyed entries out of harm but still resolves values" do
    user = make_user("ident", email: "ident@example.com", mobile: "9600000777")
    vrp = make_vrp(email: "ident@example.com", created_by_id: user.id)

    probe = Probe.new
    probe.send(:preload_vrp_creator_identity_lookups!, [vrp])
    cache = probe.instance_variable_get(:@cached_vrp_creator_users_by)

    assert_equal user.id, cache[[[:email, "ident@example.com"]]].id
  end
end
