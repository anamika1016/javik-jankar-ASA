# An Android device registered for push, owned by the farmer who last signed
# in on it.
class FarmerDevice < ApplicationRecord
  belongs_to :farmer_app_login

  # A token identifies a phone, not a person. When a different farmer signs in
  # on the same handset FCM reuses the token, so it moves rather than being
  # duplicated -- otherwise the previous farmer would keep getting the new
  # farmer's state's notifications.
  def self.register!(login:, token:, platform: nil, app_version: nil)
    value = token.to_s.strip
    return if value.blank?

    device = find_or_initialize_by(token: value)
    device.assign_attributes(
      farmer_app_login: login,
      platform: platform.to_s.first(40).presence || device.platform || "android",
      app_version: app_version.to_s.first(40).presence || device.app_version,
      last_seen_at: Time.current
    )
    device.save!
    device
  end

  # Tokens for every farmer who should receive a post for this state. A post
  # with no state goes to everyone.
  def self.tokens_for_state(state_id)
    scope = joins(:farmer_app_login)
    scope = scope.where(farmer_app_logins: { state_id: state_id }) if state_id.present?
    scope.distinct.pluck(:token)
  end
end
