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

    # Prefer the current role from the User record. If present, it
    # reflects the latest office mapping (e.g., FCO‑Ranapur). If the role is
    # missing, fall back to any saved suffix that may have been stored.
    if user.role.present?
      "#{name} (#{user.role})"
    elsif saved_suffix.present?
      "#{name} #{saved_suffix}"
    else
      name
    end
  end

  private

  def key(value)
    value.to_s.strip.downcase.squish
  end
end
