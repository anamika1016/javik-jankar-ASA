# Wrong-OTP lockout for the Android farmer login, counted per mobile number.
#
# Counting per OTP would be no protection at all: someone could request a
# fresh OTP after every third guess and carry on indefinitely.
class FarmerLoginLock < ApplicationRecord
  # More than three wrong OTPs locks the number for an hour.
  MAX_WRONG_ATTEMPTS = 3
  LOCK_DURATION = 1.hour

  def self.for_mobile(mobile)
    normalized = FarmerAppLogin.normalize_mobile(mobile)
    return if normalized.blank?

    find_by(mobile_no: normalized)
  end

  # Returns the lock when the number is barred right now, otherwise nil. An
  # expired lock is cleared on the way past, so the hour genuinely ends.
  def self.active_lock(mobile)
    lock = for_mobile(mobile)
    return if lock.blank?

    if lock.locked_until.present? && lock.locked_until <= Time.current
      lock.update!(locked_until: nil, failed_attempts: 0)
      return
    end

    lock.locked_until.present? ? lock : nil
  end

  def self.register_failure!(mobile)
    normalized = FarmerAppLogin.normalize_mobile(mobile)
    return if normalized.blank?

    lock = find_or_initialize_by(mobile_no: normalized)
    lock.failed_attempts = lock.failed_attempts.to_i + 1
    lock.last_failed_at = Time.current
    lock.locked_until = LOCK_DURATION.from_now if lock.failed_attempts > MAX_WRONG_ATTEMPTS
    lock.save!
    lock
  end

  # A successful login wipes the slate: the farmer proved they hold the phone.
  def self.clear!(mobile)
    normalized = FarmerAppLogin.normalize_mobile(mobile)
    return if normalized.blank?

    where(mobile_no: normalized).update_all(failed_attempts: 0, locked_until: nil, updated_at: Time.current)
  end

  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def minutes_remaining
    return 0 unless locked?

    [((locked_until - Time.current) / 60.0).ceil, 1].max
  end

  def attempts_left
    [MAX_WRONG_ATTEMPTS - failed_attempts.to_i, 0].max
  end
end
