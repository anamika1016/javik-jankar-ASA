class SlowQueryTrace
  def self.message(duration_ms, sql, locations = caller_locations, metadata = {})
    operation = sql.to_s.lstrip[/\A\w+/].to_s.upcase
    return unless %w[SELECT WITH INSERT UPDATE DELETE].include?(operation)

    root = Rails.root.to_s + "/"
    location = locations.find { |frame| frame.path.start_with?(root + "app/") && frame.path != __FILE__ }
    source = location ? "#{location.path.delete_prefix(root)}:#{location.lineno}" : "unavailable"
    category = metadata[:name] == "SCHEMA" ? "schema" : "application"
    async = metadata[:async] == true
    "PERFORMANCE_SQL duration_ms=#{duration_ms.round(1)} operation=#{operation} source=#{source} category=#{category} async=#{async}"
  end

  def self.attach(threshold_ms)
    return unless threshold_ms.positive?

    ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, started, finished, _id, payload|
      duration_ms = (finished - started) * 1000
      next if duration_ms < threshold_ms || payload[:cached]

      message = message(duration_ms, payload[:sql], caller_locations, payload)
      Rails.logger.info(message) if message
    end
  end
end
