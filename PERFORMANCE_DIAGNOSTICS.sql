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
COMMIT;
