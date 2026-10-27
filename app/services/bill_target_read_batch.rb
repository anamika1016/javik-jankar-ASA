# Request-local target reads for scoped bill totals. Calculations still execute
# separately for each owner, retaining the legacy scoped/unscoped fallback.
class BillTargetReadBatch
  ORDER = %i[month_name vrp_id village_name main_activity_name activity_name id].freeze
  attr_reader :records

  def initialize(owner_ids:, months:, month_number:)
    @owner_ids = owner_ids.map { |id| id.to_i }.uniq
    @months = months.map { |month| month.to_s.strip.downcase }.uniq
    @month_number = month_number
    scope = TargetMapping.where(vrp_id: @owner_ids)
    # SQL computes canonical normalization, preserving PostgreSQL LOWER/BTRIM
    # semantics rather than substituting Ruby's broader whitespace stripping.
    headers = scope.pluck(:id, :vrp_id, :month_name, Arel.sql("LOWER(BTRIM(month_name))"))
    @normalized_months = headers.to_h { |id, _owner, _raw, normalized| [id, normalized] }
    numbers = @months.filter_map { |month| @month_number.call(month) }.uniq
    all_months = @months.any? { |month| month.blank? || @month_number.call(month).nil? }
    ids = headers.filter_map do |id, _owner, raw, normalized|
      id if all_months || @months.include?(normalized) || numbers.include?(@month_number.call(raw))
    end
    @records = scope.where(id: ids).order(*ORDER).to_a
    @by_owner = @records.group_by { |record| record.vrp_id.to_i }
  end

  def covers?(owner_ids, month)
    owner_ids.present? && owner_ids.all? { |id| @owner_ids.include?(id.to_i) } && @months.include?(month.to_s.strip.downcase)
  end

  def records_for(owner_ids:, month:, scoped_owner_ids: nil)
    owners = owner_ids.map(&:to_i).uniq
    # Filtering the ordered array keeps PostgreSQL's original collation/order.
    candidates = owners.one? ? (@by_owner[owners.first] || []) : @records.select { |record| owners.include?(record.vrp_id.to_i) }
    scoped = scoped_owner_ids.nil? ? candidates : candidates.select { |record| scoped_owner_ids.include?(record.vrp_id.to_i) }
    month_key = month.to_s.strip.downcase
    exact = ->(rows) { month.present? ? rows.select { |record| @normalized_months[record.id] == month_key } : rows }
    rows = exact.call(scoped)
    rows = exact.call(candidates) if rows.empty?
    if month.present? && rows.empty?
      number = @month_number.call(month)
      rows = number ? candidates.select { |record| @month_number.call(record.month_name) == number } : candidates
    end
    rows
  end
end
