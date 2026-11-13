# Sends a published news item or video to the phones that should get it.
#
# Runs in the background on purpose: a broadcast can touch thousands of
# devices and each one is its own FCM call, which must not be charged to the
# admin who pressed Publish.
class FarmerPushBroadcastJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = FarmerPushMessage.find_by(id: message_id)
    return if message.blank? || message.status != "Pending"

    item = message.notifiable
    return message.update!(status: "Skipped", error: "The post was deleted before sending.") if item.blank?
    return message.update!(status: "Skipped", error: "The post is no longer active.") unless item.active?

    tokens = FarmerDevice.tokens_for_state(message.state_id)
    message.update!(device_count: tokens.size)
    return message.update!(status: "Skipped", error: nothing_to_send_reason) if tokens.empty?

    result = FcmClient.send_notification(
      tokens: tokens, title: message.title, body: message.body,
      data: push_data(message, item)
    )

    # A token FCM rejects as dead belongs to an app that was uninstalled or
    # reinstalled; keeping it would mean retrying it on every broadcast.
    FarmerDevice.where(token: result.dead_tokens).delete_all if result.dead_tokens.present?

    message.update!(
      sent_count: result.sent, failed_count: result.failed, sent_at: Time.current,
      status: result.sent.positive? ? "Sent" : "Failed",
      error: failure_reason(result)
    )
  end

  private

  # "No farmer in this state" reads like a state-matching problem even when
  # no phone has registered anywhere, which is the usual case before the app
  # ships. Say which of the two it actually is.
  def nothing_to_send_reason
    total = FarmerDevice.count
    if total.zero?
      "No farmer has registered the app for notifications yet, in any state. " \
        "The app must call POST /api/v1/farmer/devices after login."
    else
      "No farmer in this state has registered yet. " \
        "#{total} device#{'s' if total != 1} registered in other states."
    end
  end

  def push_data(message, item)
    {
      type: message.notifiable_type == "FarmerVideo" ? "video" : "news",
      id: item.id,
      state_id: message.state_id,
      # So the app can open straight to the item instead of just the list.
      deep_link: message.notifiable_type == "FarmerVideo" ? "farmer://videos/#{item.id}" : "farmer://news/#{item.id}"
    }
  end

  def failure_reason(result)
    case result.error
    when :not_configured
      "Firebase is not configured on this server, so nothing was sent."
    when :auth_failed
      "Firebase rejected the server credentials."
    when :exception
      "Firebase could not be reached."
    else
      result.failed.positive? ? "#{result.failed} device(s) rejected the message." : nil
    end
  end
end
