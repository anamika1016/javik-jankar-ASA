module GloballyUniqueUsername
  extend ActiveSupport::Concern

  included do
    validate :username_is_globally_unique
  end

  private

  def username_is_globally_unique
    return unless username_uniqueness_source?

    username = username_for_global_uniqueness.to_s.strip
    return if username.blank?
    return unless username_taken_in_users?(username) ||
      username_taken_in_vrps?(username) ||
      username_taken_in_module_records?(username)

    if respond_to?(:user_name)
      errors.add(:user_name, "has already been taken")
    else
      errors.add(:base, "User Name has already been taken")
    end
  end

  def username_uniqueness_source?
    !is_a?(ModuleRecord) || module_slug.to_s == "new-user"
  end

  def username_for_global_uniqueness
    return user_name if respond_to?(:user_name)

    data.to_h["user_name"].presence || data.to_h[:user_name]
  end

  def username_taken_in_users?(username)
    return false unless User.table_exists?

    scope = User.where("LOWER(TRIM(user_name)) = ?", username.downcase)
    scope = scope.where.not(id: id) if is_a?(User) && persisted?
    scope.exists?
  end

  def username_taken_in_vrps?(username)
    return false unless Vrp.table_exists?

    scope = Vrp.unscoped.where("LOWER(TRIM(user_name)) = ?", username.downcase)
    scope = scope.where.not(id: id) if is_a?(Vrp) && persisted?
    scope.exists?
  end

  def username_taken_in_module_records?(username)
    return false unless ModuleRecord.table_exists?

    scope = ModuleRecord.where(module_slug: "new-user")
      .where("LOWER(TRIM(COALESCE(data::jsonb->>'user_name', ''))) = ?", username.downcase)
    scope = scope.where.not(id: id) if is_a?(ModuleRecord) && persisted?
    scope.exists?
  end
end
