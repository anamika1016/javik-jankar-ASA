require "test_helper"

class SlowQueryTraceTest < ActiveSupport::TestCase
  test "trace never emits query literals credentials or binding data" do
    message = SlowQueryTrace.message(1234.56, "SELECT 'private-password', 'farmer-phone' FROM users", [])
    assert_includes message, "duration_ms=1234.6"
    assert_includes message, "operation=SELECT"
    refute_includes message, "private-password"
    refute_includes message, "farmer-phone"
    refute_includes message, "FROM users"
  end

  test "trace distinguishes schema metadata and async work without exposing query names" do
    message = SlowQueryTrace.message(1000, "SELECT 'private'", [], { name: "SCHEMA", async: true })
    assert_includes message, "category=schema async=true"
    ordinary = SlowQueryTrace.message(1000, "SELECT 'private'", [], { name: "Private user name" })
    assert_includes ordinary, "category=application async=false"
    refute_includes ordinary, "Private user name"
  end

  test "arbitrary SQL text cannot become a log operation" do
    assert_nil SlowQueryTrace.message(2000, "secret-user-input", [])
  end
end
