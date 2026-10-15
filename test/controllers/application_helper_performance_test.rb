require "test_helper"

class ApplicationHelperPerformanceTest < ActiveSupport::TestCase
  test "stakeholder lookup keeps username precedence with one user query" do
    username_user = User.create!(
      user_name: "sidebar_lookup_preferred_#{SecureRandom.hex(4)}",
      password: "secret", stakeholder: "Username stakeholder"
    )
    id_user = User.create!(
      user_name: "sidebar_lookup_id_#{SecureRandom.hex(4)}",
      password: "secret", stakeholder: "ID stakeholder"
    )

    helper = Object.new.extend(ApplicationHelper)
    helper.define_singleton_method(:current_app_user) do
      { "id" => id_user.id, "username" => username_user.user_name, "stakeholder" => nil }
    end

    user_queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      user_queries += 1 if sql.match?(/FROM\s+["`]?users["`]?/i) && !payload[:cached]
    end

    names = helper.current_user_stakeholder_names

    assert_equal ["Username stakeholder"], names
    assert_equal 1, user_queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
