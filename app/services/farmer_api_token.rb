# Session token for the Android farmer app.
#
# Separate from ApiAuthToken by design: these two token families are signed
# with different keys, so a farmer token is rejected by every existing
# Jeevika Jankar / staff endpoint and vice versa.
class FarmerApiToken
  PURPOSE = :farmer_api_auth
  DEFAULT_TTL = 30.days

  def self.encode(farmer_app_login, expires_in: DEFAULT_TTL)
    verifier.generate(
      {
        "login_id" => farmer_app_login.id,
        "exp" => expires_in.from_now.to_i
      },
      purpose: PURPOSE
    )
  end

  def self.decode(token)
    return if token.blank?

    data = verifier.verify(token.to_s, purpose: PURPOSE)
    return if data["exp"].to_i < Time.current.to_i

    data
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
    nil
  end

  def self.find_login(token)
    data = decode(token)
    return unless data

    FarmerAppLogin.find_by(id: data["login_id"])
  end

  def self.verifier
    Rails.application.message_verifier("farmer_app_api_token_v1")
  end
  private_class_method :verifier
end
