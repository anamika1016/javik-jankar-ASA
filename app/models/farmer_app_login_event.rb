# One sign-in from the Android app. farmer_app_logins carries the farmer and
# their latest state; this carries the history a date filter reads.
class FarmerAppLoginEvent < ApplicationRecord
  belongs_to :farmer_app_login

  scope :on_date, ->(date) { where(logged_in_at: date.all_day) }
end
