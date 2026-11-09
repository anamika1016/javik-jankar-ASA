# RAILS_ENV=test bundle exec rails runner script/training_revision_performance_audit.rb
require "securerandom"
require "tmpdir"
abort "Use a dedicated test database" unless Rails.env.test?

def timed
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = yield
  [(1000 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)).round(2), value]
end

previous_cache = Rails.cache
shared_directory = Dir.mktmpdir("jj-revision-audit-")
Rails.cache = ActiveSupport::Cache::FileStore.new(shared_directory)
begin
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.uncached do
      now = Time.current
      rows = 500.times.map do |index|
        { module_slug: TrainingEditApproval::SLUG, created_at: now, updated_at: now,
          data: { "record_id" => "audit-#{index / 2}", "status" => index.even? ? "Approved" : "Pending",
            "before" => { "photo" => SecureRandom.hex(16000) }, "proposed" => { "photo" => SecureRandom.hex(16000) } } }
      end
      ModuleRecord.insert_all!(rows)
      original = lambda do
        ModuleRecord.where(module_slug: TrainingEditApproval::SLUG)
          .order(Arel.sql("(data::jsonb ->> 'record_id'), id DESC"))
          .pluck(Arel.sql("DISTINCT ON ((data::jsonb ->> 'record_id')) (data::jsonb ->> 'record_id')"),
            Arel.sql("data::jsonb ->> 'status'"))
          .filter_map { |id, status| id.to_s if id.to_s.present? && status != "Approved" }
      end
      TrainingEditApproval::REVISION_READ_CACHE.clear
      cold_ms, cold = timed { TrainingEditApproval.unapproved_record_ids }
      measurements = 5.times.map do
        before_ms, expected = timed { original.call }
        after_ms, actual = timed { TrainingEditApproval.unapproved_record_ids }
        raise "Approval behavior changed" unless expected == actual && cold == actual
        TrainingEditApproval::REVISION_READ_CACHE.clear
        shared_ms, shared = timed { TrainingEditApproval.unapproved_record_ids }
        raise "Cross-worker approval behavior changed" unless shared == expected
        { original_ms: before_ms, cached_ms: after_ms, simulated_second_worker_ms: shared_ms }
      end
      puts JSON.pretty_generate(environment: Rails.env, synthetic_revision_count: rows.size,
        note: "Local synthetic reads; writes rolled back; not a production latency promise",
        cold_ms: cold_ms, measurements: measurements)
      raise ActiveRecord::Rollback
    end
  end
ensure
  Rails.cache = previous_cache
  FileUtils.remove_entry(shared_directory) if shared_directory && File.directory?(shared_directory)
end
