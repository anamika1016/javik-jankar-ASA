# Slow read diagnostics contain timings/counts only, never records or parameters.
# GC/allocation/CPU deltas are process-wide when Puma threads overlap.
class ReadStageTrace
  def self.measure(stage, threshold_ms: nil)
    threshold_ms ||= Float(ENV.fetch("PERFORMANCE_STAGE_LOG_MS", Rails.env.production? ? "250" : "0"), exception: false)
    return yield unless threshold_ms&.positive?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    gc = GC.stat(:time)
    allocations = GC.stat(:total_allocated_objects)
    result = yield
  ensure
    if started
      begin
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        if elapsed >= threshold_ms
          count = result.is_a?(Array) || result.is_a?(Hash) ? " items=#{result.length}" : ""
          count = " bytes=#{result.bytesize}" if result.is_a?(String)
          Rails.logger.info("PERFORMANCE_STAGE stage=#{stage} duration_ms=#{elapsed.round(1)} " \
            "cpu_process_ms=#{((Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu) * 1000).round(1)} " \
            "gc_process_ms=#{GC.stat(:time) - gc} allocations_process=#{GC.stat(:total_allocated_objects) - allocations}#{count}")
        end
      rescue StandardError
        # Optional telemetry must not replace a read's result or exception.
        nil
      end
    end
  end
end
