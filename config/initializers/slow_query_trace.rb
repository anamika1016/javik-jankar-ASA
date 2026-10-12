# Opt-in diagnostics: log duration and application callsite, never SQL/binds.
Rails.application.config.after_initialize do
  threshold = Float(ENV.fetch("PERFORMANCE_SQL_LOG_MS", "0"), exception: false)
  SlowQueryTrace.attach(threshold) if threshold&.positive?
end
