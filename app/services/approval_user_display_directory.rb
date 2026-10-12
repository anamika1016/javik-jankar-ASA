# Resolve saved approval labels against the same User records as All User.
# The old role is a display snapshot, not the identity used for lookup.
class ApprovalUserDisplayDirectory
  def initialize
    users = User.select(:id, :user_name, :first_name, :last_name, :email, :role).to_a
    @by_username = users.group_by { |user| key(user.user_name) }
    @by_name = users.group_by { |user| key(user.full_name) }
    @by_email = users.group_by { |user| key(user.email) }
  end

  def label(value)
    original = value.to_s
    identity = key(original.sub(/\s*\([^)]*\)\s*\z/, ""))
    return original if identity.blank?

    matches = @by_username[identity] || @by_email[identity] || @by_name[identity]
    return original unless matches&.one?

    user = matches.first
    name = user.full_name.presence || user.user_name
    user.role.present? ? "#{name} (#{user.role})" : name
  end

  private

  def key(value)
    value.to_s.strip.downcase.squish
  end
end
