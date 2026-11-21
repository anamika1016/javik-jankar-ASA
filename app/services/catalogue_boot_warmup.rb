# Puma cluster bootstrap only; ordinary runners/migrations do not call this.
class CatalogueBootWarmup
  def self.run(environment: Rails.env, enabled: ENV.fetch("PREWARM_CATALOGUES_ON_BOOT", "1"))
    return false unless environment.to_s == "production" && enabled == "1"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Rails.logger.info("CATALOGUE_PREWARM starting before worker fork")
    if block_given?
      yield
    else
      load Rails.root.join("script/warm_form_catalogues.rb")
    end
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
    Rails.logger.info("CATALOGUE_PREWARM completed duration_ms=#{ms}")
    true
  rescue StandardError => error
    # This optional preparation must not turn an otherwise usable deployment
    # into a failed boot. Normal readers retain their original cold-fill path.
    Rails.logger.warn("CATALOGUE_PREWARM unavailable error=#{error.class}; normal cold reads remain enabled")
    false
  end
end
