import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class RequestPerformanceAnalysisTest(unittest.TestCase):
    def test_interleaved_requests_keep_their_own_timings_and_stages(self):
        first = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        second = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        lines = [
            f'[{first}] Started GET "/target_mappings?private=hidden" for 192.0.2.1',
            f'[{second}] Started GET "/modules/user-hierarchy-mapping" for 192.0.2.2',
            f'[{first}] PERFORMANCE_STAGE stage=external.jj_catalogue duration_ms=8000.5 cpu_process_ms=12.0 items=4',
            f'[{second}] Completed 200 OK in 125ms (Views: 40.0ms | ActiveRecord: 15.0ms (2 queries, 0 cached) | GC: 1.0ms)',
            f'[{first}] Completed 200 OK in 12580ms (Views: 1800.0ms | ActiveRecord: 6000.0ms (20 queries, 1 cached) | GC: 2100.0ms)',
        ]
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory, "requests.log")
            log.write_text("\n".join(lines))
            result = subprocess.run([sys.executable, "script/analyze_request_performance.py", str(log)], check=True, capture_output=True, text=True)
        report = json.loads(result.stdout)
        self.assertEqual(2, report["completed_request_count"])
        slow, fast = report["requests"]
        self.assertEqual(("/target_mappings", 12580.0), (slow["path"], slow["duration_ms"]))
        self.assertEqual(("/modules/user-hierarchy-mapping", 125.0), (fast["path"], fast["duration_ms"]))
        self.assertEqual(8000.5, slow["stages"][0]["duration_ms"])
        self.assertNotIn("stages", fast)
        self.assertNotIn("hidden", result.stdout)
        self.assertNotIn("192.0.2", result.stdout)


if __name__ == "__main__":
    unittest.main()
