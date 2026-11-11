# The record of one push broadcast: what went out, to how many phones, and
# whether FCM accepted it.
class FarmerPushMessage < ApplicationRecord
  belongs_to :notifiable, polymorphic: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  STATUSES = %w[Pending Sent Failed Skipped].freeze

  def delivered?
    status == "Sent"
  end

  # One line a non-technical reader can act on.
  def summary
    case status
    when "Sent" then "Sent to #{sent_count} of #{device_count} device#{'s' if device_count != 1}"
    when "Skipped" then error.presence || "Nothing to send to"
    when "Failed" then error.presence || "Sending failed"
    else "Queued"
    end
  end
end
