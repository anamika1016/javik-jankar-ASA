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
    # Extract any parenthetical suffix already present in the saved label
    # e.g. "Pritesh Jain (FCO-Ranapur)" → suffix = "(FCO-Ranapur)"
    saved_suffix = original.match(/\s*(\([^)]*\))\s*\z/)&.captures&.first
    identity = key(original.sub(/\s*\([^)]*\)\s*\z/, ""))
    return original if identity.blank?

    matches = @by_username[identity] || @by_email[identity] || @by_name[identity]
    return original unless matches&.one?

    user = matches.first
    name = user.full_name.presence || user.user_name

    # If the saved label already had a parenthetical suffix (office/role tag),
    # preserve it so that an updated approval channel (e.g. FCO-Ranapur) is
    # not silently overwritten by the User's stale database role (e.g. FCO-Jobat).
    # Only fall back to User.role when no suffix was present in the original label.
    if saved_suffix.present?
      "#{name} #{saved_suffix}"
    elsif user.role.present?
      "#{name} (#{user.role})"
    else
      name
    end
  end

  private

  def key(value)
    value.to_s.strip.downcase.squish
  end
end
