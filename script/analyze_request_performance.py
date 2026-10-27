#!/usr/bin/env python3
"""Summarize Rails journal logs by request ID without exposing IPs/binds."""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

requests = {}
sources = defaultdict(lambda: {"count": 0, "total_ms": 0, "max_ms": 0, "log_lines": []})
for line_number, line in enumerate(Path(sys.argv[1]).read_text().splitlines(), 1):
    match = re.search(r"\[([0-9a-f-]{36})\] (.*)", line)
    if not match:
        continue
    request_id, event = match.groups()
    request = requests.setdefault(request_id, {"id": request_id})
    start = re.search(r'Started \w+ "([^"?]+)', event)
    if start:
        request["path"] = start.group(1)
        request["log_line"] = line_number
    sql = re.search(r"PERFORMANCE_SQL duration_ms=([\d.]+).* source=(\S+)", event)
    if sql:
        duration, source = sql.groups()
        entry = sources[source]
        entry["count"] += 1
        entry["total_ms"] += float(duration)
        entry["max_ms"] = max(entry["max_ms"], float(duration))
        entry["log_lines"].append(line_number)
    complete = re.search(r"Completed (\d+).* in ([\d.]+)ms", event)
    if complete:
        request["status"], request["duration_ms"] = int(complete[1]), float(complete[2])
        request["completed_log_line"] = line_number
        for label in ["Views", "ActiveRecord", "GC"]:
            value = re.search(label + r": ([\d.]+)ms", event)
            if value:
                request[label + "_ms"] = float(value[1])
        counts = re.search(r"\((\d+) quer(?:y|ies), (\d+) cached\)", event)
        if counts:
            request["queries"], request["cached_queries"] = map(int, counts.groups())
print(json.dumps({"requests": sorted(requests.values(), key=lambda row: row.get("duration_ms", 0), reverse=True),
    "sql_sources": sorted(({"source": key, **value} for key, value in sources.items()),
                          key=lambda row: row["total_ms"], reverse=True)}, indent=2))
