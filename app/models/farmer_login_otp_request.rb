require "digest"

# One issued farmer-login OTP. Durable on purpose: single-use and the
# wrong-attempt count are security state, not cache.
class FarmerLoginOtpRequest < ApplicationRecord
  self.table_name = "farmer_login_otps"

  scope :unexpired, -> { where(expires_at: Time.current..) }

  def self.digest(otp)
    Digest::SHA256.hexdigest("farmer-login-otp:#{otp.to_s.strip}")
  end

  def expired?
    expires_at.blank? || expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  # What became of this OTP. The code itself is never stored, so this is what
  # the web list can honestly report about it.
  def status
    return :used if consumed?
    return :expired if expired?

    :waiting
  end

  def status_label
    case status
    when :used then "Verified"
    when :waiting then "Awaiting entry"
    else attempts.to_i.positive? ? "Expired after #{attempts} try" : "Expired unused"
    end
  end

  # Counts the try and consumes the row in one statement each, so two requests
  # racing with the same OTP cannot both be told they succeeded.
  def register_attempt!
    self.class.where(id: id).update_all("attempts = attempts + 1, updated_at = NOW()")
    reload.attempts
  end

  def consume!
    self.class.where(id: id, consumed_at: nil).update_all(consumed_at: Time.current) == 1
  end
end
