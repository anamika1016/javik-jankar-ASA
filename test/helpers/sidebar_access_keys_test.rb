require "test_helper"

# The sidebar permission keys used to be wrapped in Rails.cache. On this
# deployment the cache store lives in the database, so that lookup cost one
# query to build the fingerprint for the key and another to read the entry -
# and a miss added a delete and an insert - all to avoid a single small read of
# the access-control records.
#
# These tests pin that the keys themselves are unchanged and that computing
# them now takes one query per request.
class SidebarAccessKeysTest < ActionView::TestCase
  include ApplicationHelper

  attr_accessor :app_user
  def current_app_user = app_user

  def access_record(names, overrides = {})
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => names, "can_view" => "Yes", "status" => "Active",
      "stakeholder_name" => "ASA", "role" => "Agronomist"
    }.merge(overrides))
  end

  def count_queries
    n = 0
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      n += 1 unless sql.start_with?("SHOW", "BEGIN", "COMMIT", "SAVEPOINT", "RELEASE")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    n
  end

  setup do
    access_record(["Dashboard", "Training Form"])
    access_record(["Jeevika Jankar Registration"])
    access_record(["Hidden Module"], "can_view" => "No")
    access_record(["Deleted Module"], "deleted" => "yes")
    access_record(["Other Org Module"], "stakeholder_name" => "Other Org")
    self.app_user = {
      "id" => 1, "username" => "sidebar_user", "stakeholder" => "ASA",
      "role" => "Agronomist", "user_type" => "User"
    }
  end

  test "the permitted keys match what the access-control records allow" do
    keys = allowed_sidebar_keys

    assert_includes keys, "dashboard"
    assert_includes keys, "training-form"
    assert_includes keys, "jeevika-jankar-registration"
    assert_not_includes keys, "hidden-module", "can_view No must stay excluded"
    assert_not_includes keys, "deleted-module", "a deleted record must stay excluded"
    assert_not_includes keys, "other-org-module", "another stakeholder must stay excluded"
  end

  test "computing the keys costs one query per request" do
    queries = count_queries { allowed_sidebar_keys }

    assert_equal 1, queries,
      "the sidebar should read the access-control records once and nothing else"
  end

  test "the keys are memoised, so repeated reads in a request add no queries" do
    allowed_sidebar_keys
    queries = count_queries { 5.times { allowed_sidebar_keys } }

    assert_equal 0, queries
  end

  test "an admin keeps the unrestricted sidebar" do
    self.app_user = { "id" => 2, "username" => "admin", "user_type" => "admin" }

    assert_nil allowed_sidebar_keys,
      "nil means no restriction, which is how an admin sees every menu"
  end

  test "a signed-out visitor is unrestricted and costs nothing" do
    self.app_user = nil

    queries = count_queries { assert_nil allowed_sidebar_keys }
    assert_equal 0, queries
  end

  test "a newly added permission is visible on the next request" do
    first = allowed_sidebar_keys
    assert_not_includes first, "other-target"

    access_record(["Other Target"])
    remove_instance_variable(:@allowed_sidebar_keys)
    remove_instance_variable(:@active_sidebar_access_records)

    assert_includes allowed_sidebar_keys, "other-target",
      "without the cache a new permission must take effect immediately"
  end
end
