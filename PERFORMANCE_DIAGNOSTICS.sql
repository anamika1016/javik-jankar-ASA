-- JJ diagnostic snapshot: reads statistics only, no application row contents.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SELECT now() AS captured_at, current_database() AS database;
SELECT pid, application_name, state, wait_event_type, wait_event,
       now() - query_start AS active_duration, pg_blocking_pids(pid) AS blockers
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
  AND state IS DISTINCT FROM 'idle'
ORDER BY query_start;
SELECT datname, numbackends, blks_read, blks_hit, temp_files, temp_bytes,
       deadlocks, stats_reset
FROM pg_stat_database WHERE datname = current_database();
SELECT relname, n_live_tup, n_dead_tup, seq_scan, idx_scan,
       last_analyze, last_autoanalyze, last_autovacuum
FROM pg_stat_user_tables
WHERE relname IN ('module_records', 'target_mappings', 'vrps', 'afls', 'users');
SELECT relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE relname IN ('module_records', 'target_mappings', 'vrps', 'afls', 'users')
ORDER BY relname, indexrelname;
-- Verify the actual deployed indexes, including interrupted concurrent builds.
SELECT tab.relname AS table_name, idx.relname AS index_name,
       pi.indisvalid, pi.indisready, pg_get_indexdef(pi.indexrelid) AS definition
FROM pg_index pi
JOIN pg_class idx ON idx.oid = pi.indexrelid
JOIN pg_class tab ON tab.oid = pi.indrelid
JOIN pg_namespace ns ON ns.oid = tab.relnamespace
WHERE ns.nspname = 'public'
  AND tab.relname IN ('module_records', 'target_mappings', 'vrps', 'afls', 'users')
ORDER BY tab.relname, idx.relname;
SELECT version FROM schema_migrations
WHERE version IN ('20261005130000', '20261005140000') ORDER BY version;
SELECT relname, pg_size_pretty(pg_relation_size(relid)) AS heap_size,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE relname IN ('module_records', 'target_mappings', 'vrps', 'afls', 'users');
COMMIT;
