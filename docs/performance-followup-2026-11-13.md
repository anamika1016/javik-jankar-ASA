# Additional performance and behavior review — 13 November 2026

This follow-up reviews the current worktree after the preceding Bill List and training fallback corrections. No production deployment or live-server latency measurement was performed.

## New optimization

`dashboard_training_candidates_for_target` already indexed monthly training records by owner. It nevertheless rebuilt, deduplicated and sorted the same candidate positions for every activity target belonging to the same JJ. It now reuses that candidate list within the request and source-record snapshot.

The key contains all normalized owner identity values. Changing a name, username or mobile produces a separate key; a new source array has a separate source index. Results preserve source order, duplicate rows and the existing blank-owner fallback. Each caller still receives a fresh outer array. Retention is bounded per source snapshot to 128 identities and 100,000 record references; a large shared blank-owner population therefore does not create an unbounded cache of candidate arrays.

The final target, assignment, approval and farmer matching rules are unchanged. No business calculations, permissions, schema or production JavaScript were changed in this follow-up. The unrelated existing `db/schema.rb` diff was retained.

## Measurements

CPU-only synthetic selection benchmark: 3,000 training records, 100 owners, 1,000 targets, including blank owner records shared across owners.

| Metric | Before | After |
|---|---:|---:|
| Candidate selection time | 65.07 ms | 19.30 ms |
| Allocations | 105,750 | 95,135 |

All candidate lists and their ordering match the original helper. This measures candidate preparation, not an entire page or production latency.

Reproduce with Ruby 3.4.2 and the installed bundle:

```sh
RAILS_ENV=test bundle exec rails runner script/training_owner_candidate_reuse_audit.rb
```

The comparison loads the original helper from HEAD; retain the desired baseline ref before committing if comparing later revisions.

## Verification

- **186 focused tests, 1,254 assertions, zero failures/errors.** Coverage includes billing totals, approval, staff scoping, invoices, training/farmer rendering, dashboard drilldowns, owner aliases, blank-owner fallback, source ordering, duplicate rows, changing owner identities, replacing source snapshots and caller mutation of returned arrays. The owner-scaling case now crosses the identity-cache limit.
- **46 cold/warm page renders**, all HTTP 200, no exceptions. For 42 renders, visible text, controls and browser-data hashes match the old-helper reference directly. The bundled audit again had four VRP list/approval hash mismatches, consistent with the previously recorded audit limitation. To investigate, the unchanged baseline was repeated for these routes and the current code was then run in the same isolated route workload: **all four isolated renders match** in visible text, controls, browser data and HTTP status. This is not a claim that every bundled hash is stable.
- **329 admin/staff/JJ web/API requests**, no exceptions or 5xx responses. All role/route response statuses match the old-helper reference after generated fixture IDs are normalized. Existing authorization and validation responses remain present.
- JavaScript browser stubs were repaired to provide `getElementById`, option objects and a global timer, allowing the language-switch tests to exercise the existing code rather than fail on missing mock APIs. **42 of 43 JavaScript cases pass.** One previously masked semantic mismatch remains: the English cookie test expects cookie expiry while the unchanged implementation writes `/en/en`. Production translation behavior was deliberately not changed under a performance-only change.
- Ruby syntax and whitespace checks pass.

## Remaining issues and limits

The previous complete controller/service/integration run remains **858 tests, 23 failures and 8 errors**. Its remaining 31 issues also reproduced with original production methods. That entire suite was not rerun for this narrowly scoped candidate reuse; the affected and related paths were covered by the fresh 186-test focused run and the page/role audits above. The complete issue inventory remains in [the broader rescan report](performance-final-rescan-2026-11-13.md).

The preceding fast/full Other Activity discrepancy was a real defect and was corrected to the existing full-calculation result. This follow-up preserves that correction. Matching output in tested cases is evidence against regressions, not a guarantee that all possible application issues have been eliminated. Production data volume, network latency, external APIs and server load still require measurements after deployment.
