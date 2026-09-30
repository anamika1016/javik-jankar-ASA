class AgreementVrpScope
  OFFICE_KEYS = %w[fcoc fcoc_name office_name office parent_office].freeze

  # Every screen that scopes by FCO has to cope with the same spellings of one
  # office -- "FCO-C Sausar", "FCO-Bhawanipatna", "Bhawanipatna - FCO" and
  # "Bhawanipatna" -- so reduce them all to a single comparable key.
  def self.office_key(value)
    text = normalize_text(value.to_s.split("||").last)
    text.sub(/\A(?:fcoc|fco(?:\s+c)?)(?:\s+|\z)/, "").sub(/\s+fco(?:\s+c)?\z/, "").strip
  end

  def self.normalize_text(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  # The FCO offices a staff login belongs to, however their office was spelled.
  def self.user_office_keys(user)
    user = user || {}
    roles = %w[role role_name stakeholder_role user_management_role person_type]
      .map { |key| normalize_text(user[key]) }
    keys = OFFICE_KEYS.map { |key| office_key(user[key]) }
    # Some older registrations store the FCO location in the role itself.
    keys.concat(roles.filter_map { |role| office_key(role) if role.start_with?("fco") })
    keys.compact_blank.uniq
  end

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

    # Any staff login that belongs to an FCO office sees that office's Jeevika
    # Jankars, whether or not they registered them. This covers Agronomists and
    # other office staff, not only accounts whose role begins with "FCO".
    offices = self.class.user_office_keys(@user)
    if offices.any?
      return mapped_scope { |vrp| office_key(vrp.fcoc).present? && offices.include?(office_key(vrp.fcoc)) }
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
    self.class.office_key(value)
  end

  def normalize(value)
    self.class.normalize_text(value)
  end
end
