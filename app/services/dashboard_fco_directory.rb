# Request-local office aliases for dashboard farmer and target reports.
class DashboardFcoDirectory
  class Store < ActiveSupport::CurrentAttributes
    attribute :offices
  end

  def self.bare_name(value)
    AgreementVrpScope.office_key(value).titleize
  end

  def self.offices
    Store.offices ||= begin
      # Some target mappings use office-master IDs or name IDs, while AFL uses
      # another ID. Keep every saved alias so a populated target office does not
      # disappear from farmer reports or JJ summary boxes.
      farmer_pairs = Afl.distinct.pluck(:fco_id, :fco)
      farmer_ids = farmer_pairs.map { |id, _name| id.to_s.strip }.to_set
      pairs = farmer_pairs + TargetMapping.distinct.pluck(:fco_id, :fco_name)
      pairs.group_by { |id, _name| id.to_s.strip }.filter_map do |id, rows|
        next if invalid?(id)
        names = rows.map { |_id, name| name.to_s.strip }.reject { |name| invalid?(name) }.uniq.sort
        label = names.first || id
        { id: id, name: bare_name(label), raw_name: label, aliases: names, farmer_master: farmer_ids.include?(id) }
      end.sort_by { |office| [office[:name], office[:farmer_master] ? 0 : 1, office[:id]] }
    end
  end

  def self.invalid?(value)
    value.blank? || %w[null nil none n/a -].include?(value.to_s.downcase)
  end

  def self.names
    offices.map { |office| office[:name] }.uniq
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

  def self.offices_for(value)
    key = AgreementVrpScope.office_key(value)
    return [] if key.blank?
    offices.select do |office|
      office[:id] == value.to_s.strip ||
        [office[:name], *office[:aliases]].any? { |name| AgreementVrpScope.office_key(name) == key }
    end
  end

  def self.office_for(value)
    offices_for(value).first
  end

  def self.ids_for(value)
    offices_for(value).map { |office| office[:id] }.uniq
  end

  def self.id_for(value)
    office_for(value)&.dig(:id)
  end

  def self.name_for(value)
    office_for(value)&.dig(:name) || value.to_s
  end

  def self.aliases_for(value)
    offices_for(value).flat_map do |office|
      [office[:id], office[:name], office[:raw_name], *office[:aliases], "FCO-C #{office[:name]}", "FCO-#{office[:name]}"]
    end.uniq
  end

  def self.filter_values
    offices.flat_map { |office| aliases_for(office[:id]) }
  end
end
