# The TO (territory office) a list row belongs to, for lists that already show
# the FCO. A row's TO is its Jeevika Jankar's own TO, the same one the bill
# list and the printed invoice use; a row with no known Jeevika Jankar falls
# back to the TO the Jeevika Jankars of its FCO are under.
#
# One instance reads the Jeevika Jankar offices once, so a long list costs a
# single query.
class JeevikaJankarToName
  def initialize
    rows = Vrp.where.not(to_name: [nil, ""]).pluck(:id, :fcoc, :to_name)
    @by_vrp_id = rows.to_h { |id, _fcoc, to_name| [id.to_s, to_name.strip] }
    @by_fco = rows.group_by { |_id, fcoc, _to_name| self.class.fco_key(fcoc) }
      .except("")
      .transform_values { |group| group.map { |_id, _fcoc, to_name| to_name.strip }.tally.max_by(&:last).first }
  end

  def for(vrp_id: nil, fco: nil)
    @by_vrp_id[vrp_id.to_s.strip].presence || @by_fco[self.class.fco_key(fco)].presence || "-"
  end

  # "FCO-Bhawanipatna", "Bhawanipatna - FCO" and "Bhawanipatna" are one FCO.
  def self.fco_key(name)
    name.to_s.downcase.gsub(/\bfco\b/, "").gsub(/[^a-z0-9]/, "")
  end
end
