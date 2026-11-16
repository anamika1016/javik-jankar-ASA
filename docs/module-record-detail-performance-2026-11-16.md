# module_records entry/detail/edit rescan — 16 November 2026

Follow-up to `new-log-performance-2026-11-16.md`. Earlier uncommitted performance work was retained. This pass focuses on unnecessary `module_records` data in entry/edit and eye/detail navigation, rather than assuming that every delay comes from this table. The supplied journal also shows upstream API waits and GC.

## Changes

1. Entry and edit forms for other-target, other-target-with-farmer, seed-distribution-target, papl360-target, approval-master, access-control, vrp-bill-add, jeevika-jankar-bill-process and jeevika-jankar-transfer no longer load/sort every sibling record into unused `@records`. These view branches render their form without a saved-record table. The original selected-record read, authorization, form dependencies and save/validation actions remain. Screens that actually show saved records still load them; integration tests retain master edit pagination/search.
2. JJ detail label helpers batch selected project/GP/village IDs instead of querying once per selected ID. Request-local caches include missing rows and keep the slug constraint, original label aliases, ID conversion, selection order, repeated labels and literal fallbacks. Selected record payloads remain complete.
3. `ModuleRecordReadQuery.field_value_rows` reads only required JSON dropdown values. The bill-form catalogue reader keeps its original active scope, newest-first order, per-key presence filtering, array/comma handling and duplicates, while avoiding unrelated uploads and model instantiation.
4. `ModuleRecordReadQuery.projected_data_rows` provides a reusable JSON projection for GP name/location lookups. It retains location/alias/status/deletion fields and excludes unrelated uploads/history. Ruby active/deleted checks and lookup precedence remain.
5. Bill eye/detail, print and attachment actions announce their single selected bill before authorization/history readers run. The existing history helper therefore fetches that bill's history instead of every bill's history. Its ordering and authorization predicates are unchanged.
6. Shared catalogue code fingerprints now include `module_record_read_query.rb`, so future helper changes invalidate persisted derived catalogues too.

No database migration, business-record write, new background job, production deployment or worker restart was performed. The existing prewarm script remains available. No response was made stale merely to avoid a query, and no loader was hidden in this pass.

## Measured local results

Isolated PostgreSQL synthetic fixtures, query cache disabled during measurements, external HTTP blocked and fixture writes rolled back. Baseline helper methods come from commit `f0f51c0`; entry/edit baseline explicitly restores the previous sibling-list read. These numbers are not production latency or a guarantee for every page.

| Case | Before ms | After ms | Queries before/after | Models before/after | Parity |
|---|---:|---:|---:|---:|---|
| Entry with 5,000 sibling records | 170.17 | 14.58 | 16/15 | 5001/1 | Equal |
| Edit with 5,000 sibling records | 92.62 | 13.98 | 17/16 | 5002/2 | Equal |
| Detail: 200 selected labels | 32.92 | 4.5 | 201/1 | 200/200 | Equal |
| Dropdown: 300 records with large JSON | 13.99 | 11.87 | 1/1 | 300/0 | Equal |
| GP lookup: 300 records with large JSON | 11.81 | 13.0 | 1/1 | 0/0 | Equal |

Entry/edit comparison checks the complete `.module-page` HTML after removing CSRF tokens. Label/dropdown/GP comparisons check the exact returned result. GP projection reduces transferred fields and allocations, but this local run is slower (13.0 versus 11.81 ms); it is not claimed as a measured wall-time improvement. PostgreSQL must still parse the JSON to project it. Production network/large-data benefit needs measurement.

## Validation

- Combined targeted regressions: **224 tests, 1,506 assertions, zero failures/errors**. Coverage includes actual GETs of all nine entry/edit forms under a guard that raises on sibling-list reads; selected form action; real saved-table screens; label batching, ordering, duplicates, literal/missing/cross-slug IDs; projected JSON types/nulls/quoted keys; bill detail/history/print checks; earlier billing, scope, approval, cache and form regressions.
- Final render audit: 46/46 synthetic cold/warm renders return 200.
- Role audit: 329 requests — 308×200, 9×401, 9×403, 2×302, 1×422; no exceptions or 5xx. This audit ran before the final selected-bill-history adjustment, which has separate targeted and full-suite coverage.
- Full Rails suite: **926 tests, 8,165 assertions, 23 failures and 8 errors**. The 31 failing/error test names exactly match the preceding baseline; no new names appeared. The full suite is not green. The earlier report records the baseline failure inventory.
- Ruby syntax checks and `git diff --check` pass. There are no new JavaScript changes in this follow-up; prior navigation tests are described in the earlier report.

These checks support the reviewed cases, not a blanket claim that every possible production workflow is issue-free. Real data volume, concurrent load, external APIs, transfer time and browser rendering still affect navigation. A maximum complete-page time of 15 ms is not established.

## Reproduction and rollout

Run only on the dedicated isolated test database:

```sh
RAILS_ENV=test bundle exec rails runner script/module_record_detail_read_audit.rb
```

After deploying the complete pending performance changes, run the already provided prewarm command as the application user on each host:

```sh
RAILS_ENV=production bundle exec rails runner script/warm_form_catalogues.rb
```

Then remeasure production entry, list, selected eye/detail, edit and print requests under real concurrent traffic. No changes have been deployed from this workspace.

Artifacts: `tmp/module_record_detail_read_audit.json`, `tmp/detail_read_combined_tests.log`, `tmp/detail_read_all_regression_tests.log`, `tmp/detail_read_render_audit.json`, `tmp/detail_read_role_audit.json`.
