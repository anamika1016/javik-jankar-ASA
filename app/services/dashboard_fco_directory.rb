# Request-local office directory for dashboard reports. AFL is authoritative.
class DashboardFcoDirectory
  class Store < ActiveSupport::CurrentAttributes
    attribute :offices
  end

  def self.bare_name(value)
    AgreementVrpScope.office_key(value).titleize
  end

  def self.offices
    Store.offices ||= Afl.where.not(fco_id: [nil, ""]).distinct.pluck(:fco_id, :fco)
      .filter_map do |id, name|
        next if %w[null nil none n/a -].include?(id.to_s.strip.downcase)
        label = name.to_s.strip
        label = id.to_s if label.blank? || %w[null nil none n/a -].include?(label.downcase)
        { id: id.to_s.strip, name: bare_name(label), raw_name: label }
      end.uniq { |office| office[:id] }.sort_by { |office| office[:name] }
  end

  def self.names
    offices.map { |office| office[:name] }
  end

  def self.ids
    offices.map { |office| office[:id] }
  end

  def self.name_by_id
    offices.to_h { |office| [office[:id], office[:name]] }
  end

  def self.id_by_name
    offices.to_h { |office| [office[:name].downcase, office[:id]] }
  end

  def self.office_for(value)
    key = AgreementVrpScope.office_key(value)
    offices.find { |office| office[:id] == value.to_s.strip || AgreementVrpScope.office_key(office[:name]) == key }
  end

  def self.id_for(value)
    office_for(value)&.dig(:id)
  end

  def self.name_for(value)
    office_for(value)&.dig(:name) || value.to_s
  end

  def self.aliases_for(value)
    office = office_for(value)
    office ? [office[:id], office[:name], office[:raw_name], "FCO-C #{office[:name]}", "FCO-#{office[:name]}"] : []
  end

  def self.filter_values
    offices.flat_map { |office| aliases_for(office[:id]) }
  end
end
