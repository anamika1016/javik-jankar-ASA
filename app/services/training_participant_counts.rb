# Count attendance independently of the selected, registered farmer IDs.
class TrainingParticipantCounts
  def self.number(value)
    text = value.to_s.strip
    return nil unless text.match?(/\A\d+\z/)

    text.to_i
  end

  def self.data(data)
    result = data.deep_dup
    male = number(data["male_count"])
    female = number(data["female_count"])
    result["male_count"] = male.to_s unless male.nil?
    result["female_count"] = female.to_s unless female.nil?
    selected_count = Array(data["selected_farmer_ids"]).map(&:to_s).compact_blank.uniq.size
    result["farmer_count"] = selected_count.to_s if data.key?("selected_farmer_ids")
    result["total_farmer_count"] = selected_count.to_s
    result
  end

  # Multiple activity rows can represent the same session. Attendance is entered
  # once, so do not sum it once per activity or mix counts from different rows.
  def self.for_session(records)
    record = records.select do |item|
      number(item.data["male_count"]) && number(item.data["female_count"])
    end.max_by { |item| [item.updated_at, item.id] } || records.first
    data(record.data)
  end
end
