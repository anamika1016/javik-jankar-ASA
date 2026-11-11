# Queues a push notification when a news item or video is published.
#
# The row is written first and the sending happens in a job, so an admin who
# presses Publish is never left waiting on Firebase, and there is a record to
# read afterwards whether or not delivery worked.
module FarmerBroadcastPush
  extend ActiveSupport::Concern

  included do
    has_many :push_messages, class_name: "FarmerPushMessage", as: :notifiable, dependent: :destroy

    after_create_commit :queue_push_notification
  end

  def last_push_message
    push_messages.recent_first.first
  end

  private

  def queue_push_notification
    return unless active?

    message = FarmerPushMessage.create!(
      notifiable: self, state_id: state_id,
      title: push_title, body: push_body
    )
    FarmerPushBroadcastJob.perform_later(message.id)
  end
end
