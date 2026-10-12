# The month every dashboard opens on when the user has not picked one, and the
# month a new Other Target form pre-selects.
#
# This lived as a copy-pasted `Date.current.prev_month.strftime("%B")` in the
# web dashboard, both mobile dashboard APIs and the CC / assistant reports.
# Keeping one definition means the browser and the app can never disagree
# about which month a fresh dashboard is showing.
#
# Billing screens are deliberately NOT covered here: a bill list opens on the
# month being billed, which is its own cycle.
class DashboardDefaults
  def self.month
    Date.current.strftime("%B")
  end
end
