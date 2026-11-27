# Run with: bin/rails runner script/module_table_read_audit.rb
# Read-only audit of dedicated-table IDs, payload parity and local query times.
require 'benchmark'
results = ModuleMirror::SLUG_MODELS.map do |slug, model|
  original = ModuleRecord.where(module_slug: slug).order(:id).pluck(:id, :data)
  scope = ModuleMirror.read_scope(slug).order(:id)
  rows = scope.pluck(:id, :data)
  # Mirrors intentionally normalize malformed scalar payloads to empty objects.
  expected = original.map { |id, data| [id, data.is_a?(Hash) ? data : {}] }
  elapsed = Benchmark.realtime { 3.times { ModuleRecord.uncached { scope.load.reset } } }
  { slug: slug, table: model.table_name, rows: rows.size,
    equal_ids_and_data: expected == rows, mean_read_ms: (elapsed * 1000 / 3).round(2) }
end
puts JSON.pretty_generate(ready: ModuleMirror.ready?, results: results)
abort 'Dedicated table mismatch' unless results.all? { |r| r[:equal_ids_and_data] }
