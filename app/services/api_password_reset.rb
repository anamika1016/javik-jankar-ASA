require "digest"

class ApiPasswordReset
  PURPOSE = :api_password_reset
  TTL = 10.minutes

  def self.find_account(username)
    return if username.blank?

    username_key = username.to_s.strip.downcase

    if "User".safe_constantize&.table_exists?
      user = User.where.not(status: "Inactive")
        .where("LOWER(user_name) = ?", username_key)
        .first
      return user if user
    end

    if "Vrp".safe_constantize&.table_exists? && Vrp.column_names.include?("user_name")
      scope = Vrp.all
      scope = scope.where(is_active: true) if Vrp.column_names.include?("is_active")
      scope = scope.where(is_deleted: false) if Vrp.column_names.include?("is_deleted")
      vrp = scope.where("LOWER(user_name) = ?", username_key).first
      return vrp if vrp
    end

    return unless defined?(ModuleRecord) && ModuleRecord.table_exists?

    ModuleRecord.where(module_slug: "new-user").find_each do |record|
      data = record.respond_to?(:data) ? record.data : {}
      next if data["status"].to_s.downcase == "inactive"
      return record if data["user_name"].to_s.downcase == username_key
    end

    nil
  rescue StandardError => e
    Rails.logger.warn("API password reset lookup failed: #{e.class} - #{e.message}")
    nil
  end

  def self.account_mobile(account)
    return account.mobile_no if account.respond_to?(:mobile_no)

    account.data["mobile_no"] if account.respond_to?(:data)
  end

  def self.issue(account:, username:)
    otp = SecureRandom.random_number(10_000).to_s.rjust(4, "0")
    token = verifier.generate(
      {
        "record_type" => record_type_for(account),
        "id" => account.id,
        "username" => username.to_s.strip,
        "otp_digest" => digest(otp),
        "exp" => TTL.from_now.to_i
      },
      purpose: PURPOSE
    )

    { otp: otp, reset_token: token }
  end

  def self.verify(reset_token:, otp:, username:)
    data = decode(reset_token)
    return if data.blank?
    return if data["exp"].to_i < Time.current.to_i
    return if data["username"].to_s != username.to_s.strip
    return if data["otp_digest"].to_s != digest(otp)

    find_account_by_payload(data)
  end

  def self.update_password!(account, password)
    if account.is_a?(ModuleRecord)
      account.update!(data: account.data.merge("password" => password, "confirmed_password" => password))
    else
      account.update_column(:password, password)
    end
  end

  def self.mask_mobile(mobile)
    digits = mobile.to_s.gsub(/\D/, "")
    last10 = digits.length >= 10 ? digits[-10, 10] : digits
    return "" if last10.blank?

    "#{'*' * [last10.length - 4, 0].max}#{last10.last(4)}"
  end

  def self.decode(token)
    return if token.blank?

    verifier.verify(token.to_s, purpose: PURPOSE)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
    nil
  end

  def self.find_account_by_payload(data)
    case data["record_type"]
    when "User"
      User.find_by(id: data["id"]) if "User".safe_constantize&.table_exists?
    when "Vrp"
      Vrp.find_by(id: data["id"]) if "Vrp".safe_constantize&.table_exists?
    when "ModuleRecord"
      ModuleRecord.where(module_slug: "new-user").find_by(id: data["id"]) if defined?(ModuleRecord) && ModuleRecord.table_exists?
    end
  end

  def self.digest(otp)
    Digest::SHA256.hexdigest(otp.to_s.strip)
  end

  def self.record_type_for(account)
    return account.class.name if account.is_a?(ApplicationRecord)

    "ModuleRecord"
  end

  def self.verifier
    Rails.application.message_verifier("vrp_api_password_reset_v1")
  end

  private_class_method :decode, :find_account_by_payload, :digest, :record_type_for, :verifier
end
