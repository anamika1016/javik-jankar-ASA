# Bill List and slow-page rescan — 12 November 2026

Follow-up: see [final rescan](performance-final-rescan-2026-11-13.md). The three previously tracked performance-test issues have now been investigated: the full-vs-fast Other Activity total discrepancy is fixed; two test fixtures were corrected without changing permissions. Historical timings below describe the earlier revision.

Bill List repeatedly scanned every monthly Other Target submission while calculating each JJ's totals. Scoped viewers retained separate per-owner calculations, but shared database reads still left a large Ruby processing cost.

## Changes

- Build a request-local index of monthly submissions by saved target ID and normalized owner/month. Only potentially matching rows reach the existing complete matcher. Keep saved-ID fallbacks, owner ID/name/username aliases, SQL source order, duplicate rows, approval filtering, farmer IDs and achievement calculations.
- Share the existing monthly reads with completed-farmer calculations during the scoped totals batch.
- Stop CC label resolution as soon as the existing highest-priority valid label is found, avoiding unused nested bill-item scans. Preserve placeholder handling and fallback precedence.
- Extend the existing rollback-only render audit with optional owner and Other Target fixture counts.

No schema migration, production data change, shared cross-request totals cache, filter change, or UI pagination change is included.

## Measured results

Identical synthetic scoped Bill List workload: 100 bills, 3,000 monthly Other Target records, 100 JJs, test database, external HTTP disabled, inserts rolled back. Baseline uses the methods from immediately before this Bill List change.

| Full HTTP render | Before | After | Allocations before → after |
|---|---:|---:|---:|
| Cold request | 1,515.40 ms | 435.69 ms | 6,034,501 → 827,467 |
| Warm request | 1,360.59 ms | 318.48 ms | 5,998,246 → 791,245 |

Both requests returned 200. Visible text, controls and browser data hashes match the baseline for both passes. Query counts remain 26 cold and 23 warm: this workload's gain is primarily reduced Ruby processing and allocations, not fewer queries. Warm request time improved by about 77%; allocations fell about 87%.

The separate CPU-only achievement benchmark with 100 owner scopes and 3,000 submissions measured **1,743.74 → 60.26 ms**, with **7,810,993 → 321,169 allocations**. Complete achievement outputs match the original method.

These are local synthetic measurements, not production or browser timing guarantees. The historical supplied production logs remain the original 84 requests; no new production logs were supplied for this rescan and no production deployment was performed.

## Behavior and regression checks

- **123 tests, 646 assertions, zero failures/errors** across candidate matching, scoped billing, bill list reads, approval channels/history, prepared-by labels, staff scope, invoices, resubmission, duplicate guards, mutation redirects, previous hotspots, training routing and farmer rendering.
- Candidate regression coverage includes direct saved IDs without metadata, stale saved IDs with owner matching, case/whitespace, owner names/usernames, multiple owners, absent candidates, duplicate source rows, different months, incomplete metadata, changing owner scopes, pending/rejected/inactive/deleted submissions, achievement totals and completed farmer IDs.
- Three JavaScript checks passed: bill loading, table pagination and mutation navigation.
- **46 cold/warm renders** across the existing slow-page audit: all HTTP 200, no exceptions. Small-workload Bill List renders measured 46.40/33.98 ms. Largest small-workload request measured 123.10 ms.
- **329 admin/staff/JJ web and API requests**: no 5xx responses or exceptions. Response statuses match the pre-change run for all 329 requests after normalizing generated fixture IDs. Counts: 308 successful 200 responses, 2 redirects, 9 unauthorized responses, 9 forbidden responses, and 1 validation 422 response. The staff request to `/api/v1/jeevika-jankar-dashboard` returns 422 in both runs. These statuses are not all equivalent to successful business operations; the comparison verifies no response-status regression.
- The previous broader suite was rerun: **105 tests, 642 assertions, the same 2 failures and 1 error as before**. These are the existing FCO/TO office-scope expectation, bill achievement-summary expectation, and location-cache request stub missing `filtered_parameters`. They also reproduce with original methods and remain tracked in the first audit; this change does not resolve them.
- Ruby syntax and `git diff --check` pass.

## Reproduction

Use Ruby 3.4.2, the installed bundle, `RAILS_ENV=test`, and an isolated test `DATABASE_URL`. Do not use production data.

CPU/output comparison:

```sh
bundle exec rails runner script/bill_other_target_scaling_audit.rb
```

Large Bill List HTTP workload:

```sh
RESCAN_OWNERS=100 RESCAN_OTHER_RECORDS_PER_OWNER=30 \
RESCAN_SCOPED_BILL_TOTALS=1 \
RESCAN_PATHS=/modules/jeevika-jankar-bill-list \
bundle exec rails runner script/rescan_slow_pages.rb
```

The scoped-totals flag forces only the synthetic audit's scoped calculator branch; actual permissions remain covered by the role and controller tests. The CPU benchmark loads the baseline achievement method from HEAD; preserve a baseline ref before committing if comparing revisions later.

## Production follow-up

Deploy the reviewed changes and capture Bill List requests under the affected real roles. Compare total request time, `module_records` stages, SQL, allocations/GC and response size with the supplied logs. Production data volume, server load, cold caches, external services and the deployed revision have not been measured by this local rescan. The checks provide evidence against behavior regressions within their tested cases; they do not establish that every possible issue has been eliminated.
