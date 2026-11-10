require "digest"

# OTP for the Android farmer login.
#
# The OTP itself is never stored or sent back to the app -- only its digest is
# kept, in farmer_login_otps. The app holds a signed token carrying the row's
# jti, so a token cannot be forged and an OTP cannot be read out of it.
#
# Single-use and the wrong-attempt count live in the database rather than in
# Rails.cache: a cache may drop entries, and dropping these would silently
# re-enable OTP replay and unlimited guessing.
#
# Kept separate from ApiLoginOtp on purpose -- a farmer OTP must never be
# exchangeable for a Jeevika Jankar or staff session.
class FarmerLoginOtp
  PURPOSE = :farmer_app_login_otp
  # Two minutes: long enough for an SMS to land and be typed, short enough
  # that an OTP read off a lock screen later is already dead.
  TTL = 2.minutes
  # Wrong guesses are limited per mobile number, not per OTP -- see
  # FarmerLoginLock. Requesting a new code must not buy a fresh set of tries.
  RESEND_INTERVAL = 60.seconds
  # Rows are kept well past expiry so the web list can report what happened
  # to the last OTP -- sent, used, expired, or guessed at.
  RETENTION = 24.hours

  def self.issue(farmer:, mobile:, identifier_type:, aadhaar_no: nil)
    otp = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
    jti = SecureRandom.uuid
    normalized = normalize_mobile(mobile)

    # A newly issued OTP retires any earlier one for this number, so a resend
    # cannot leave two codes working at once.
    FarmerLoginOtpRequest
      .where(mobile_no: normalized, consumed_at: nil)
      .where(expires_at: Time.current..)
      .update_all(expires_at: Time.current, updated_at: Time.current)

    FarmerLoginOtpRequest.create!(
      jti: jti,
      mobile_no: normalized,
      identifier_type: identifier_type.to_s,
      aadhaar_digest: FarmerAppLogin.aadhaar_digest_for(aadhaar_no),
      otp_digest: FarmerLoginOtpRequest.digest(otp),
      expires_at: TTL.from_now
    )
    sweep_expired

    # The register's answer is only cached -- losing it costs one extra
    # lookup at verify time, nothing more, so a cache is the right home.
    # It is not stored in the row: the payload carries an Aadhaar number.
    Rails.cache.write(farmer_key(jti), farmer, expires_in: TTL)

    token = verifier.generate({ "jti" => jti, "exp" => TTL.from_now.to_i }, purpose: PURPOSE)
    { otp: otp, otp_token: token }
  end

  # Returns the request row when the OTP matches, otherwise a symbol saying
  # why. The caller re-reads the farmer from the register; nothing about the
  # farmer is trusted from the token.
  def self.verify(otp_token:, otp:)
    data = decode(otp_token)
    return :invalid_token if data.blank?

    request = FarmerLoginOtpRequest.find_by(jti: data["jti"])
    return :invalid_token if request.blank?
    return :expired if request.expired?
    return :consumed if request.consumed?

    # Counted before the comparison, so a wrong guess always costs an attempt
    # even if the request is abandoned straight afterwards. There is no cap
    # per OTP: the limit lives on FarmerLoginLock, against the mobile number,
    # because a per-OTP cap would reset every time a new code was requested.
    request.register_attempt!

    unless ActiveSupport::SecurityUtils.secure_compare(
      request.otp_digest.to_s, FarmerLoginOtpRequest.digest(otp)
    )
      return :wrong_otp
    end

    # Loses the race rather than issuing two sessions for one OTP.
    return :consumed unless request.consume!

    request
  end

  # The number an OTP was issued to. Needed after a wrong guess, when the
  # caller has to charge the failure to the right mobile but verify has
  # already refused to hand back the row.
  def self.mobile_for(otp_token)
    data = decode(otp_token)
    return if data.blank?

    FarmerLoginOtpRequest.where(jti: data["jti"]).pick(:mobile_no)
  end

  # The register payload saved when this OTP was issued, if it is still held.
  # Returns nil once it has expired, so the caller must be ready to re-read.
  def self.issued_farmer(request)
    jti = request.respond_to?(:jti) ? request.jti : request.to_h["jti"]
    return if jti.blank?

    Rails.cache.read(farmer_key(jti))
  end

  # One OTP a minute per mobile. Without this an Aadhaar typed into the app
  # could be used to keep texting whoever that Aadhaar is registered to.
  def self.resend_blocked?(mobile)
    normalized = normalize_mobile(mobile)
    return false if normalized.blank?

    FarmerLoginOtpRequest
      .where(mobile_no: normalized)
      .where(created_at: RESEND_INTERVAL.ago..)
      .exists?
  end

  # Kept so callers read the same way as before; the row itself is the record
  # that an OTP was sent, so nothing extra has to be written here.
  def self.note_sent(_mobile)
    true
  end

  def self.mask_mobile(mobile)
    digits = normalize_mobile(mobile)
    return "" if digits.blank?

    "#{'*' * [digits.length - 4, 0].max}#{digits.last(4)}"
  end

  def self.normalize_mobile(mobile)
    digits = mobile.to_s.gsub(/\D/, "")
    digits.length >= 10 ? digits[-10, 10] : digits
  end

  # Kept for a day after expiry so the Farmer App Logins page can still show
  # the outcome of the last OTP; older rows have no further use.
  def self.sweep_expired
    FarmerLoginOtpRequest.where(expires_at: ...RETENTION.ago).delete_all
  rescue StandardError => error
    Rails.logger.warn("Farmer OTP sweep failed: #{error.class} - #{error.message}")
  end

  def self.farmer_key(jti)
    "farmer-login-otp:farmer:#{jti}"
  end

  def self.decode(token)
    return if token.blank?

    verifier.verify(token.to_s, purpose: PURPOSE)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
    nil
  end

  def self.verifier
    Rails.application.message_verifier("farmer_app_login_otp_v1")
  end

  private_class_method :decode, :verifier, :farmer_key, :sweep_expired
end
