class ApiAuthToken
  PURPOSE = :api_auth
  DEFAULT_TTL = 30.days

  def self.encode(user, expires_in: DEFAULT_TTL)
    payload = {
      "record_type" => record_type_for(user),
      "id" => user.id,
      "exp" => expires_in.from_now.to_i
    }

    verifier.generate(payload, purpose: PURPOSE)
  end

  def self.decode(token)
    return if token.blank?

    data = verifier.verify(token.to_s, purpose: PURPOSE)
    return if data["exp"].to_i < Time.current.to_i

    data
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
    nil
  end

  def self.find_user(token)
    data = decode(token)
    return unless data

    case data["record_type"]
    when "User"
      User.find_by(id: data["id"]) if "User".safe_constantize&.table_exists?
    when "Vrp"
      Vrp.find_by(id: data["id"]) if "Vrp".safe_constantize&.table_exists?
    when "ModuleRecord"
      ModuleRecord.where(module_slug: "new-user").find_by(id: data["id"]) if defined?(ModuleRecord) && ModuleRecord.table_exists?
    end
  end

  def self.record_type_for(user)
    return user.class.name if user.is_a?(ApplicationRecord)

    "ModuleRecord"
  end

  def self.verifier
    Rails.application.message_verifier("vrp_api_auth_token_v1")
  end
  private_class_method :verifier, :record_type_for
end
