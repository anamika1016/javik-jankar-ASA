Monthly training read optimization — 27 October 2026

Change and preserved behavior

The monthly training reader previously loaded every active training entry, including large photo/participant payloads, before rejecting entries with unapproved edit revisions. It now captures the same request-local blocked-ID snapshot and excludes those IDs in SQL before loading full records. The original Ruby status predicate still runs on surviving records.

TrainingEditApproval.unapproved_record_ids now reads scalar record-ID/status pairs with pluck rather than instantiating the latest revision as an Active Record object. DISTINCT ON / highest revision ID precedence and the returned ID order remain unchanged.

- No revision: eligible under the existing status rules.
- Latest status exactly Approved: revision permits counting.
- Latest null, lowercase approved, pending/rejected, numeric/array/object status: same original result.
- Highest ID wins even with an older timestamp or a deleted flag on the revision.
- Once captured, the request snapshot is reused across later monthly reads, even if approvals change in the meantime.
- Reference IDs match exactly as strings; leading zeros, whitespace and malformed IDs are not coerced into a different numeric ID.
- Result IDs, ordering, full photo/participant data and active/status filtering are preserved. No permission, amount, date default or list cap changed.

Measured local benchmark

Isolated rollback-only fixture: 200 entries with 64 KB photo strings; 180 have a pending latest revision. Both implementations return the same 20 records and full attributes in the same order. Both warmed schema metadata and disabled SQL query caching.

| Metric | Baseline | Final snapshot-preserving implementation |
| --- | ---: | ---: |
| SELECT queries | 2 | 2 |
| Instantiated Active Record objects | 380 | 20 |
| Ruby allocations | 9,316 | 3,900 |
| Local elapsed time | 20.74 ms | 6.01 ms |
| Returned entries | 20 | 20 |

The query count is intentionally unchanged: retaining the existing request snapshot avoids a cross-month behavior change. The gains come from avoiding revision objects and blocked photo payloads. The monthly EXPLAIN ANALYZE used the existing index_module_records_on_slug_normalized_month index. No new migration/index was needed. These synthetic timings do not predict production response times; GC time was zero in both small benchmark runs.

Verification

- Final focused Rails suite: 164 tests, 919 assertions, zero failures/errors. Includes billing/approval/invoice/attachment workflows, visibility integrations, legacy fallback totals, request snapshots and JSON/output parity tests.
- Full HTTP audit with half the training entries pending revision approval: all 19 pages returned 200 on cold and warm visits.
- All 38 comparisons against baseline 7dbf517 matched visible text, form values/options and browser data-* payloads exactly.
- Fixture timestamps for master/JJ/target rows are distinct to avoid undefined database ordering when sort timestamps tie. Application sorting was not changed.
- Ruby syntax and git diff --check passed. Existing historical unrelated suite failures are not represented as fixed.
- Development and production databases were not modified; test/benchmark fixtures rolled back in jj_feature_removal_test_20261026.

Reproduce

    RAILS_ENV=test DATABASE_URL=<isolated-test-db> bin/rails runner script/benchmark_monthly_training_reads.rb
    RAILS_ENV=test DATABASE_URL=<isolated-test-db> RESCAN_BLOCKED_REVISIONS=1 bin/rails runner script/rescan_slow_pages.rb
    RAILS_ENV=test DATABASE_URL=<isolated-test-db> RESCAN_BLOCKED_REVISIONS=1 RESCAN_BASELINE_REF=7dbf517 bin/rails runner script/rescan_slow_pages.rb

Remaining scale limit

The existing global revision snapshot still reads one ID/status pair per latest revision, and eligible monthly records retain their full payloads for consumers that need evidence. This change reduces wasted materialization; it does not bound every result set or certify arbitrary-scale performance. Production's 33–156 second cases still require fresh same-user/month/scope logs and runtime wait/memory measurements after deployment.
