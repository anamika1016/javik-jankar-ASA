# One sign-in from the Jeevika Jankar / staff mobile app.
class AppUserLogin < ApplicationRecord
  LOGIN_METHODS = %w[password otp].freeze

  scope :recent_first, -> { order(logged_in_at: :desc, id: :desc) }
  scope :on_date, ->(date) { where(logged_in_at: date.all_day) }

  # Called from the API the moment a login succeeds. Wrapped by the caller so
  # a problem here can never stop somebody signing in -- a missing log line
  # is a smaller failure than a locked-out field worker.
  def self.record!(payload:, method:, request: nil)
    payload = payload.to_h.with_indifferent_access
    return if payload[:id].blank?

    create!(
      record_type: payload[:record_type].presence || "User",
      record_id: payload[:id],
      name: payload[:name].presence || payload[:username],
      username: payload[:username],
      mobile_no: payload[:mobile_no],
      # A Jeevika Jankar's role arrives as their type; staff carry a role name.
      role: payload[:role_name].presence || payload[:role].presence ||
        payload[:user_management_role].presence || payload[:person_type].presence ||
        Array(payload[:vrp_types]).first,
      office_name: payload[:office_name].presence || payload[:sub_office_name].presence ||
        payload[:parent_office].presence || payload[:office],
      fcoc: payload[:fcoc],
      login_method: method.to_s.presence_in(LOGIN_METHODS) || "password",
      ip: request&.remote_ip,
      device: (request&.headers&.[]("X-Device-Name").presence || request&.user_agent).to_s.first(200).presence,
      app_version: request&.headers&.[]("X-App-Version").to_s.first(40).presence,
      logged_in_at: Time.current
    )
  end

  # Jeevika Jankar or staff, in words a reader expects.
  def user_kind
    record_type == "Vrp" ? "Jeevika Jankar" : "User"
  end

  def masked_mobile
    digits = mobile_no.to_s.gsub(/\D/, "")
    return "-" if digits.blank?

    "#{'*' * [digits.length - 4, 0].max}#{digits.last(4)}"
  end
end
