class AgreementVrpScope
  def initialize(user, policy:)
    @user = user
    @policy = policy
  end

  def resolve
    roles = %w[role role_name stakeholder_role user_management_role person_type].map { |key| normalize(@user[key]) }
    if roles.any? { |role| role.match?(/\A(?:cc|cluster)(?:\s|\z)/) }
      labels = @policy.send(:current_cluster_incharge_labels)
      return mapped_scope { |vrp| person_matches?(vrp.cluster_incharge, labels) }
    end

    if roles.any? { |role| role.match?(/\Afco(?:\s|c|\z)/) }
      offices = %w[fcoc office_name office parent_office].map { |key| office_key(@user[key]) }.compact_blank
      # Some older registrations store the FCO location in the role itself.
      offices.concat(roles.filter_map { |role| office_key(role) if role.start_with?("fco") })
      return mapped_scope { |vrp| offices.include?(office_key(vrp.fcoc)) && office_key(vrp.fcoc).present? }
    end

    Vrp.where(id: @policy.send(:dashboard_vrps).map(&:id))
  end

  private

  def mapped_scope
    ids = Vrp.select(:id, :fcoc, :cluster_incharge).select { |vrp| yield vrp }.map(&:id)
    Vrp.where(id: ids)
  end

  def person_matches?(value, labels)
    # Match names exactly after formatting normalization; do not use fuzzy names
    # to grant access to another person's signed agreements.
    name = normalize(value.to_s.sub(/\s*\([^)]*\)\s*\z/, ""))
    labels.any? { |label| normalize(label.to_s.sub(/\s*\([^)]*\)\s*\z/, "")) == name } && name.present?
  end

  def office_key(value)
    text = normalize(value.to_s.split("||").last)
    text.sub(/\A(?:fcoc|fco(?:\s+c)?)(?:\s+|\z)/, "").sub(/\s+fco(?:\s+c)?\z/, "").strip
  end

  def normalize(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end
end
