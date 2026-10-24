#!/usr/bin/env bash
# Run while opening a slow page. No application writes or service restart.
set -euo pipefail

task_database="${1:-javika_production}"
task_samples="${2:-6}"
if [[ ! "$task_samples" =~ ^[0-9]+$ ]] || (( task_samples < 1 || task_samples > 30 )); then
  echo "Sample count must be between 1 and 30." >&2
  exit 1
fi

systemctl show javik -p MainPID -p ActiveEnterTimestamp -p NRestarts \
  -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p Result -p ExecMainStatus
# Show only concurrency settings, never dump the complete environment/secrets.
systemctl show javik --value -p Environment |
  tr ' ' '\n' | sed -nE 's/^"?((RAILS_MAX_THREADS|WEB_CONCURRENCY)=[^" ]+)"?$/\1/p'
journalctl -u javik --since '15 minutes ago' --no-pager -n 300 |
  sed -nE '/timed out|SIGKILL|memory peak|Min threads|Max threads|Listening|worker.*(boot|timeout|terminated)/p'
# Proxy errors distinguish connection refusal/process death from read timeouts.
if sudo -n test -r /var/log/nginx/error.log; then
  sudo -n tail -n 80 /var/log/nginx/error.log |
    sed -E 's/\?[^" ]*/?[REDACTED]/g'
fi
for ((task_sample=1; task_sample<=task_samples; task_sample++)); do
  date -u '+%Y-%m-%d %H:%M:%S UTC'
  ps -eo pid,ppid,comm,pcpu,pmem,rss --sort=-pcpu | sed -n '1,16p'
  if command -v vmstat >/dev/null; then
    vmstat 1 2
  fi
  sudo -u postgres psql -X -d "$task_database" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SELECT now() AS captured_at, pid, application_name, state,
       wait_event_type, wait_event, now()-query_start AS active_duration,
       pg_blocking_pids(pid) AS blockers
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
  AND state IS DISTINCT FROM 'idle'
ORDER BY query_start;
SELECT numbackends, blks_read, blks_hit, temp_files, temp_bytes, deadlocks, stats_reset
FROM pg_stat_database WHERE datname = current_database();
COMMIT;
SQL
  if ((task_sample < task_samples)); then sleep 2; fi
done
