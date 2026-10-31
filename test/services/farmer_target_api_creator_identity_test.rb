require "test_helper"

# The mobile API has its own visibility code. It carried the same flaw the web
# screens did: a login can be a User, a Vrp or a new-user ModuleRecord, those
# tables keep separate id sequences, and the creator id was compared without
# the creator's type - so User 9 was treated as the author of a record Vrp 9
# had saved. stamp_target_record_creator! already writes the type, so these
# tests pin that reading it back now matters.
class FarmerTargetApiCreatorIdentityTest < ActiveSupport::TestCase
  COLLIDING_ID = 4242

  def api_for(record_type:, id: COLLIDING_ID)
    FarmerTargetApi.new(module_slug: "training-form", current_app_user: {
      "id" => id, "record_type" => record_type, "username" => "ganesh_cc",
      "name" => "Ganesh Lokhande", "email" => "ganesh_cc@example.com"
    })
  end

  def record(extra)
    ModuleRecord.new(module_slug: "training-form", data: {
      "month" => "October", "fco_name" => "FCO-Bhawanipatna",
      "trainer_name" => "Jyosnamayi Suna"
    }.merge(extra.transform_keys(&:to_s)))
  end

  test "a User login does not claim a record created by the Vrp with the same id" do
    saved_by_jj = record(created_by_id: COLLIDING_ID.to_s, created_by_record_type: "Vrp",
      created_by_username: "mahesh_jj")

    assert_not api_for(record_type: "User").send(:created_by_current_user?, saved_by_jj),
      "the API let a User claim a Jeevika Jankar's record because the ids collided"
  end

  test "the Vrp that created it still owns it" do
    saved_by_jj = record(created_by_id: COLLIDING_ID.to_s, created_by_record_type: "Vrp",
      created_by_username: "mahesh_jj")

    assert api_for(record_type: "Vrp").send(:created_by_current_user?, saved_by_jj),
      "the Jeevika Jankar lost ownership of a record they created"
  end

  test "a User still owns a record they created" do
    mine = record(created_by_id: COLLIDING_ID.to_s, created_by_record_type: "User",
      created_by_username: "ganesh_cc")

    assert api_for(record_type: "User").send(:created_by_current_user?, mine)
  end

  test "a record saved before the type was stored keeps the old id match" do
    legacy = record(created_by_id: COLLIDING_ID.to_s)

    assert api_for(record_type: "User").send(:created_by_current_user?, legacy),
      "a legacy record without a creator type stopped matching its owner"
  end

  test "a different id never matches, whatever the type" do
    other = record(created_by_id: "999999", created_by_record_type: "User")

    assert_not api_for(record_type: "User").send(:created_by_current_user?, other)
  end

  test "matching on the creator's name and email is unaffected" do
    by_name = record(created_by_username: "ganesh_cc")

    assert api_for(record_type: "User").send(:created_by_current_user?, by_name),
      "the username fallback stopped working"
  end
end
