# Read-only audit. Does not migrate, rewrite data or make network requests.
# bin/rails runner script/module_retirement_audit.rb > tmp/module_retirement_audit.json
require "digest"
connection = ModuleRecord.connection
counts = ModuleRecord.group(:module_slug).count.sort.to_h
checks = ModuleMirror::SLUG_MODELS.map do |slug, model|
  source = ModuleRecord.where(module_slug: slug).select(:id, :data, :created_at, :updated_at)
  target = model.respond_to?(:for_slug) ? model.for_slug(slug) : model.all
  result = connection.select_one(<<~SQL.squish)
    SELECT COUNT(*) FILTER (WHERE old.id IS NOT NULL) AS source_rows,
      COUNT(*) FILTER (WHERE fresh.id IS NOT NULL) AS dedicated_rows,
      COUNT(*) FILTER (WHERE old.id IS NULL OR fresh.id IS NULL) AS missing_or_extra_ids,
      COUNT(*) FILTER (WHERE old.id IS NOT NULL AND fresh.id IS NOT NULL AND
        (CASE WHEN jsonb_typeof(old.data::jsonb) = 'object' THEN old.data::jsonb ELSE '{}'::jsonb END)
          IS DISTINCT FROM fresh.data) AS payload_mismatches,
      COUNT(*) FILTER (WHERE old.id IS NOT NULL AND fresh.id IS NOT NULL AND
        (old.created_at IS DISTINCT FROM fresh.created_at OR old.updated_at IS DISTINCT FROM fresh.updated_at)) AS timestamp_mismatches,
      COUNT(*) FILTER (WHERE old.id IS NOT NULL AND jsonb_typeof(old.data::jsonb) IS DISTINCT FROM 'object') AS non_object_source_payloads
    FROM (#{source.to_sql}) old
    FULL OUTER JOIN (#{target.select(:id, :data, :created_at, :updated_at).to_sql}) fresh ON old.id = fresh.id
  SQL
  { slug: slug, table: model.table_name, primary_key: model.primary_key,
    **result.transform_keys(&:to_sym).transform_values(&:to_i) }
end

migrations = Dir[Rails.root.join("db/migrate/*.rb")].sort.map do |path|
  source = File.read(path)
  RubyVM::InstructionSequence.compile(source, path)
  { file: File.basename(path), lines: source.lines.size, sha256: Digest::SHA256.hexdigest(source) }
end
query_sites = Dir[Rails.root.join("app/**/*.rb")].sort.flat_map do |path|
  source = File.read(path)
  matches = []
  source.to_enum(:scan, /ModuleRecord\s*\.\s*(?:where|find_by!?|find|all|new|create!?|insert_all!?|upsert_all!?|transaction)\b/).each do
    match = Regexp.last_match
    matches << { file: Pathname(path).relative_path_from(Rails.root).to_s,
      line: source[0...match.begin(0)].count("\n") + 1, call: match[0].gsub(/\s+/, " ") }
  end
  matches
end
unmapped = counts.reject { |slug, _count| ModuleMirror.model_for(slug) }
menu_sources = ModulesController::MODULES.keys.map { |slug| ModulesController::RECORD_SOURCE_SLUGS.fetch(slug, slug) }.uniq.sort
report = {
  note: "Inventory for this database only. A matching local copy is not proof of production parity. Query sites include safe fallbacks and write paths; they are not executed-query counts.",
  database: connection.current_database, rails_environment: Rails.env,
  safe_to_remove_module_records: false,
  blockers: [
    "Unmigrated data types still have source rows (see unmapped_data_types).",
    "Create/update/delete/import and approval mutations still write module_records; the new tables are one-way read mirrors.",
    "Read versions, generic legacy fallbacks, authentication and creator identity compatibility still depend on module_records.",
    "Independent dedicated-table inserts cannot yet replace the shared ID allocation and transactional source-version contract."
  ],
  migration_files: migrations, migrations_pending: ActiveRecord::MigrationContext.new(Rails.root.join("db/migrate")).needs_migration?,
  mirror_ready: ModuleMirror.ready?, route_functions_match: ModuleMirror.sync_routes_installed?,
  enabled_sync_triggers: connection.select_values("SELECT tgname FROM pg_trigger WHERE tgrelid = 'module_records'::regclass AND NOT tgisinternal AND tgenabled IN ('O','A') ORDER BY tgname"),
  unmapped_data_types: unmapped,
  menu_sources_without_mirror: menu_sources.reject { |slug| ModuleMirror.model_for(slug) }.to_h { |slug| [slug, counts.fetch(slug, 0)] },
  dedicated_table_checks: checks, potential_source_query_sites: query_sites
}
puts JSON.pretty_generate(report)
abort "Mirror ID, payload or timestamp mismatch" if checks.any? { |row| %i[missing_or_extra_ids payload_mismatches timestamp_mismatches].any? { |key| row[key] != 0 } }
