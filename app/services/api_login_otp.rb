require "digest"

class ApiLoginOtp
  PURPOSE = :api_login_otp
  TTL = 10.minutes

  def self.issue(user:, mobile:)
    otp = SecureRandom.random_number(10_000).to_s.rjust(4, "0")
    token = verifier.generate(
      {
        "record_type" => record_type_for(user),
        "id" => user.id,
        "mobile" => normalize_mobile(mobile),
        "otp_digest" => digest(otp),
        "exp" => TTL.from_now.to_i
      },
      purpose: PURPOSE
    )

    { otp: otp, otp_token: token }
  end

  def self.verify(otp_token:, otp:, mobile:)
    data = decode(otp_token)
    return if data.blank?
    return if data["exp"].to_i < Time.current.to_i
    return if data["mobile"].to_s != normalize_mobile(mobile)
    return if data["otp_digest"].to_s != digest(otp)

    find_user(data)
  end

  def self.find_vrp_by_mobile(mobile)
    last10 = normalize_mobile(mobile)
    return if last10.blank? || last10.length != 10
    return unless "Vrp".safe_constantize&.table_exists?

    scope = Vrp.all
    scope = scope.where(is_active: true) if Vrp.column_names.include?("is_active")
    scope = scope.where(is_deleted: false) if Vrp.column_names.include?("is_deleted")

    scope
      .where("RIGHT(regexp_replace(COALESCE(mobile_no, ''), '[^0-9]', '', 'g'), 10) = ?", last10)
      .order(:id)
      .first
  end

  def self.mask_mobile(mobile)
    last10 = normalize_mobile(mobile)
    return "" if last10.blank?

    "#{'*' * [last10.length - 4, 0].max}#{last10.last(4)}"
  end

  def self.normalize_mobile(mobile)
    digits = mobile.to_s.gsub(/\D/, "")
    return digits[-10, 10] if digits.length >= 10

    digits
  end

  def self.decode(token)
    return if token.blank?

    verifier.verify(token.to_s, purpose: PURPOSE)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
    nil
  end

  def self.find_user(data)
    case data["record_type"]
    when "Vrp"
      Vrp.find_by(id: data["id"]) if "Vrp".safe_constantize&.table_exists?
    when "User"
      User.find_by(id: data["id"]) if "User".safe_constantize&.table_exists?
    when "ModuleRecord"
      ModuleRecord.where(module_slug: "new-user").find_by(id: data["id"]) if defined?(ModuleRecord) && ModuleRecord.table_exists?
    end
  end

  def self.digest(otp)
    Digest::SHA256.hexdigest(otp.to_s.strip)
  end

  def self.record_type_for(user)
    return user.class.name if user.is_a?(ApplicationRecord)

    "ModuleRecord"
  end

  def self.verifier
    Rails.application.message_verifier("vrp_api_login_otp_v1")
  end

  private_class_method :decode, :find_user, :digest, :record_type_for, :verifier
end
