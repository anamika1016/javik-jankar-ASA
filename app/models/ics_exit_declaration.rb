class IcsExitDeclaration < ApplicationRecord
  belongs_to :farmer_farm_information, optional: true

  before_validation :default_declaration_date
  before_validation :default_status

  validates :farm_id, :farmer_name, :declaration_date, presence: true
  validates :status, inclusion: { in: %w[Active Inactive] }

  SEARCHABLE_COLUMNS = %i[
    farm_id farmer_name id_number farmer_contact_no farmer_village tracenet_no ics_name
    grower_group_name certification_status new_certification_body status
  ].freeze

  def self.search(query)
    query = query.to_s.strip
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query)}%"
    where(
      SEARCHABLE_COLUMNS.map { |column| "#{connection.quote_column_name(column)}::text ILIKE :query" }.join(" OR "),
      query: pattern
    )
  end

  private

  def default_declaration_date
    self.declaration_date ||= Date.current
  end

  def default_status
    self.status = "Active" if status.blank?
  end
end
