require "test_helper"

# The application layout asks for the current user's stakeholder on every page,
# including the login screen where nobody is signed in. Signed out, the lookup
# reduced to "user_name = '' OR id IS NULL" - a condition no row can satisfy,
# because user_name is required - so the login page paid for a full scan of the
# users table to be told nil. These tests pin that the signed-out answer is
# unchanged and that the query no longer runs.
class StakeholderNamesSignedOutTest < ActionView::TestCase
  include ApplicationHelper

  attr_accessor :app_user

  def current_app_user = app_user

  def user_queries(&block)
    queries = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      queries << sql if sql.match?(/SELECT.*FROM "users"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    queries
  end

  setup do
    @signed_in = User.create!(
      user_name: "stake_user", password: "secret", first_name: "Stake",
      stakeholder: "ASA", user_type: "User", status: "Active"
    )
    User.create!(
      user_name: "other_user", password: "secret", first_name: "Other",
      stakeholder: "Other Org", user_type: "User", status: "Active"
    )
  end

  test "signed out the stakeholder names are empty and no users query runs" do
    self.app_user = nil

    names = nil
    queries = user_queries { names = current_user_stakeholder_names }

    assert_equal [], names
    assert_empty queries,
      "the layout still scanned the users table for a visitor who is not signed in"
  end

  test "an empty app user payload behaves the same as being signed out" do
    self.app_user = {}

    names = nil
    queries = user_queries { names = current_user_stakeholder_names }

    assert_equal [], names
    assert_empty queries
  end

  test "signed in by username the stakeholder still resolves" do
    self.app_user = { "username" => "stake_user" }

    names = nil
    queries = user_queries { names = current_user_stakeholder_names }

    assert_equal ["ASA"], names
    assert_equal 1, queries.size, "the signed-in lookup must still run exactly once"
  end

  test "signed in by id alone the stakeholder still resolves" do
    self.app_user = { "id" => @signed_in.id }

    assert_equal ["ASA"], current_user_stakeholder_names
  end

  test "a stakeholder carried on the payload is kept alongside the looked-up one" do
    self.app_user = { "username" => "other_user", "stakeholder" => "Payload Org" }

    assert_equal ["Payload Org", "Other Org"], current_user_stakeholder_names
  end
end
