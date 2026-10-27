require "test_helper"
require "timeout"

class DashboardCacheFillTest < ActiveSupport::TestCase
  teardown do
    DashboardCacheFill::REGISTRY_LOCK.synchronize { DashboardCacheFill::LOCKS.clear }
  end

  test "unrelated cache fills do not wait behind a slow fill" do
    entered = Queue.new
    release = Queue.new
    first = Thread.new do
      DashboardCacheFill.synchronize(["slow", 1]) do
        entered << true
        release.pop
      end
    end
    Timeout.timeout(1) { entered.pop }

    second = Thread.new { DashboardCacheFill.synchronize(["fast", 2]) { entered << :fast } }
    assert_equal :fast, Timeout.timeout(1) { entered.pop }
  ensure
    release << true if release && first&.alive?
    first&.join
    second&.join
  end

  test "the same key still coalesces concurrent fills" do
    entered = Queue.new
    release = Queue.new
    first = Thread.new do
      DashboardCacheFill.synchronize("same") do
        entered << :first
        release.pop
      end
    end
    assert_equal :first, Timeout.timeout(1) { entered.pop }
    second = Thread.new { DashboardCacheFill.synchronize("same") { entered << :second } }

    assert_raises(Timeout::Error) { Timeout.timeout(0.05) { entered.pop } }
    release << true
    assert_equal :second, Timeout.timeout(1) { entered.pop }
  ensure
    release << true if release && first&.alive?
    first&.join
    second&.join
  end
end
