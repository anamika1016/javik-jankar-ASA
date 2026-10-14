# Opt-in diagnostics: log duration and application callsite, never SQL/binds.
Rails.application.config.after_initialize do
  # Production request totals alone cannot identify the SQL callsite behind a
  # shared slowdown. Keep development and test quiet, while production records
  # only operations above the bounded threshold (without SQL or bind values).
  default_threshold = Rails.env.production? ? "750" : "0"
  threshold = Float(ENV.fetch("PERFORMANCE_SQL_LOG_MS", default_threshold), exception: false)
  SlowQueryTrace.attach(threshold) if threshold&.positive?
end
