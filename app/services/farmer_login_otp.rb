require "digest"

# OTP for the Android farmer login. Stateless like ApiLoginOtp: the OTP digest
# travels in a signed token, so no pending-OTP table is needed and a token
# minted for one farmer cannot be replayed for another.
#
# Kept separate from ApiLoginOtp on purpose -- a farmer OTP must never be
# exchangeable for a Jeevika Jankar or staff session.
class FarmerLoginOtp
  PURPOSE = :farmer_app_login_otp
  TTL = 10.minutes
  MAX_ATTEMPTS = 5
  RESEND_INTERVAL = 60.seconds

  def self.issue(farmer:, mobile:, identifier_type:, aadhaar_no: nil)
    otp = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
    jti = SecureRandom.uuid
    # Hold the register's answer against this one OTP so verifying it does not
    # have to call the register a second time. Keyed by jti, so it is reachable
    # whether the farmer typed a mobile number or an Aadhaar.
    Rails.cache.write(farmer_key(jti), farmer, expires_in: TTL)

    token = verifier.generate(
      {
        "farmer_id" => farmer["id"].to_s,
        "mobile" => normalize_mobile(mobile),
        "identifier_type" => identifier_type.to_s,
        "aadhaar_digest" => FarmerAppLogin.aadhaar_digest_for(aadhaar_no),
        "otp_digest" => digest(otp),
        "jti" => jti,
        "exp" => TTL.from_now.to_i
      },
      purpose: PURPOSE
    )

    { otp: otp, otp_token: token }
  end

  # Returns the token payload when the OTP matches, otherwise a symbol saying
  # why. The caller re-reads the farmer from the register; nothing about the
  # farmer is trusted from the token except which farmer it was issued for.
  def self.verify(otp_token:, otp:)
    data = decode(otp_token)
    return :invalid_token if data.blank?
    return :expired if data["exp"].to_i < Time.current.to_i

    attempts = burn_attempt(data["jti"])
    return :too_many_attempts if attempts > MAX_ATTEMPTS
    return :consumed if consumed?(data["jti"])
    return :wrong_otp unless ActiveSupport::SecurityUtils.secure_compare(data["otp_digest"].to_s, digest(otp))

    consume!(data["jti"])
    data
  end

  # The register payload saved when this OTP was issued, if it is still held.
  # Returns nil once it has expired, so the caller must be ready to re-read.
  def self.issued_farmer(data)
    return if data.blank?

    Rails.cache.read(farmer_key(data["jti"]))
  end

  # One OTP a minute per mobile. Without this an Aadhaar typed into the app
  # could be used to keep texting whoever that Aadhaar is registered to.
  def self.resend_blocked?(mobile)
    key = throttle_key(mobile)
    return false if key.blank?

    Rails.cache.exist?(key)
  end

  def self.note_sent(mobile)
    key = throttle_key(mobile)
    Rails.cache.write(key, true, expires_in: RESEND_INTERVAL) if key.present?
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

  def self.throttle_key(mobile)
    digits = normalize_mobile(mobile)
    digits.present? ? "farmer-login-otp:throttle:#{digits}" : nil
  end

  def self.burn_attempt(jti)
    key = "farmer-login-otp:attempts:#{jti}"
    count = Rails.cache.read(key).to_i + 1
    Rails.cache.write(key, count, expires_in: TTL)
    count
  end

  def self.consumed?(jti)
    Rails.cache.exist?("farmer-login-otp:used:#{jti}")
  end

  def self.consume!(jti)
    Rails.cache.write("farmer-login-otp:used:#{jti}", true, expires_in: TTL)
  end

  def self.farmer_key(jti)
    "farmer-login-otp:farmer:#{jti}"
  end

  def self.digest(otp)
    Digest::SHA256.hexdigest("farmer-login-otp:#{otp.to_s.strip}")
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

  private_class_method :digest, :decode, :verifier, :burn_attempt, :consumed?, :consume!,
    :throttle_key, :farmer_key
end
