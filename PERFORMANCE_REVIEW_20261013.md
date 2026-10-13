# Performance review — 13 October 2026

## Evidence

Read the original 4,566 journal lines and matched Started/Processing/Completed entries by request UUID (877 completions with ActiveRecord metrics). Overlapping requests invalidate adjacent-line attribution:

| Request | Total | ActiveRecord | Queries |
| --- | ---: | ---: | ---: |
| Training target farmers | 137.637 s | 129.018 s | 46 |
| Bill Process | 134.177 s | 53.847 s | 27 |
| Bill Process | 126.428 s | 120.369 s | 37 |
| Bill List | 94.386 s | 29.771 s | 35 |
| Dashboard | 31.058 s | 25.349 s | 111 |
| JJ API list | 8.738 s | 3.709 s | 1,128 |
| JJ API approvals | 23.753 s | 16.756 s | 1,064 |

The quoted 134-second Other Target and 31-second Bill Process rows were misattributed. The latest 401-line follow-up still shows Bill List 66.983 s, VRP detail 70.885 s, a 14-query VRP list 51.384 s, and training target farmers 35.925 s. Its identified login POSTs completed in 26 and 50 ms; the redirect destination can still be slow. These are server request durations, not browser/network/queue timing. Views, ActiveRecord and GC counters are not independent durations to add together.

The production snapshot at 07:36:06 UTC confirms earlier performance migrations are applied and all 56 listed indexes valid/ready. No active requests were captured at that instant; this does not rule out waits during the slow interval. It reports 9,103 temporary files / 47,474,565,120 bytes (44.2 GiB) cumulatively, with no stats-reset time supplied. This is not current memory usage or the cost of one request. Module records' last recorded autoanalyze was August 3; a current query plan is needed before asserting stale statistics caused the delay.

## Behavior-preserving changes

- API JJ list preloads bank associations and approval histories. Approval queue preloads the same histories before running its original eligibility predicates.
- Approval-history batching preserves the original Ruby `to_i` matching and `created_at ASC` ordering, including numeric JSON IDs and legacy `00044` / `44legacy` strings. An exact JSON ID filter would have changed the result and was deliberately avoided.
- Repeated creator-ID lookups, exact creator-email misses, actor-email discovery, type-label results and module-label rows are reused within a request. Original type query ordering, literal fallbacks, fields and permissions remain in place. Unique creator-email/mobile approval-identity reads can still remain; this does not claim all N+1 paths are eliminated.
- Local farmer IDs for identical village-ID arrays are reused across target mappings within a request. Mapped IDs, village population, external IDs, ordering and missing-record fallbacks remain unchanged.
- Added non-unique `afls(village_id)` index with concurrent creation. The production inventory confirms it was missing: existing `(fco_id, ics_id, village_id)` has a different leading key. Existing planner choices remain PostgreSQL's decision.

No JavaScript, pagination contract, payment calculation, approval predicates, SMS, login authentication or dashboard counting logic changed in this follow-up. No production deployment, restart, migration or SMS was performed.

Separate working-copy edits appeared late in the review: `VrpsController#office_scoped_vrps` now excludes cluster-incharge office widening, and `ModulesController#jeevika_jankar_bill_record_visible?` adds mapped-JJ bill visibility for staff. These are access-logic changes, not the performance edits. The new mapped-JJ fallback initially ran for non-CC staff too and caused two visibility-test errors. Added a CC-only guard matching that branch's comment; Agronomist/FCOC retain the original office rule. The full-suite baseline comparison below predates these separate access edits; relevant focused tests are rechecked afterward. This workspace cannot accurately be described as having no access-logic changes.

## Validation

Compared the complete list payload and approval-queue IDs/order against the unchanged committed concern loaded from an isolated archive, using rollback-only synthetic data:

| 30-JJ comparison | Before SELECTs | After SELECTs | Output |
| --- | ---: | ---: | --- |
| List row construction | 124 | 36 | Complete payload equal |
| Approval queue | 31 | 2 | Same IDs and order |

Twenty targets using one village execute one local farmer SELECT and retain the original mapped/local/external ID order. These counts are scoped local measurements, not production end-to-end query counts.

On 25,000 rollback-only synthetic farmer rows, the village query used the new index: `Index Scan using index_afls_on_village_id`, 3 shared buffer hits, 0.038 ms measured execution. Without the index it used a sequential scan, 324 shared buffer hits and 2.484 ms. Synthetic local timings do not predict production latency. Migration succeeded on the isolated local test database.

Final full suite, including the separate access edits and CC-only guard: **350 tests, 2,309 assertions, 19 failures, 6 errors**. Unchanged committed baseline: **347 tests, 2,262 assertions, 19 failures, 6 errors**. Compared all 25 failure/error names: identical, no introduced failures. Final focused API/performance/office/bill-visibility run: **32 tests, 169 assertions, zero failures/errors**. The suite was and remains not fully green. `git diff --check` and diagnostic shell syntax check passed.

## Capture the remaining live delay

Read-only runtime capture now records CPU/process memory, run queue/I/O wait, PostgreSQL waits/blockers and changes in temporary-file counters over several samples. It prints process names, not command-line arguments or SQL values. Start it in one terminal, then open a slow page while it is running:

```bash
bash script/performance_runtime_snapshot.sh javik_jankar_asa_production 6 | tee performance_runtime.txt
```

The first vmstat row and ps CPU percentages are cumulative/average; subsequent vmstat rows give interval activity. This capture does not restart the service or write application records. If the file has not been deployed, deploy the reviewed diagnostic file with the code changes first.

For precise application callsites, the existing optional tracer accepts `PERFORMANCE_SQL_LOG_MS=1000` in the service environment after a normal application restart. It logs only duration, operation and source line; it does not log SQL or bind values. It remains disabled by default. Preserve the deployment's multi-database configuration; this checkout's single-database defaults differ from the live configuration.

The remaining 50–150-second delays with 10–40 queries and high GC cannot be declared solved from static code or an idle database snapshot. The runtime capture is needed to distinguish database waits, temp-file spills and Ruby/CPU contention before changing runtime settings or more complex query semantics.
