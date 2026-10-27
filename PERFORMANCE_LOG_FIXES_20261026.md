Performance log investigation and fixes — 26 October 2026

Evidence and scope

Read all 475 lines of the supplied journal excerpt and grouped events by request ID. The source lines match baseline commit 7dbf517db931e15ba173cba5db8ba90fee322851. Current source lines have moved after the fixes. Logs identify callsites, not SQL text, plans, row counts, waits or the logged-in user's scope.

The original priority table conflates separate requests:

| Request ID prefix | Page | Total | SQL count | Relevant detail |
| --- | --- | ---: | ---: | --- |
| 6dd3f0a0 | payment-list | 156,816 ms | 28 | Views 87,146 ms; AR 69,095 ms; GC 8,164 ms |
| 4d2ee0db | bill-list | 89,380 ms | 27 | Views 88,617 ms; omitted from the original priority table |
| 3263d593 | training-form | 60,694 ms | 20 | AR 58,517 ms; one traced operation 33,223 ms |
| ed28ef1c | payment-list | 54,251 ms | 405 | 93 cached; a distinct request, not another copy of the 156-second request |
| cd22e631 | payment-list | 47,937 ms | 401 | 93 cached; another distinct request |
| ee3b7d2b | payment-list-detail | 14,331 ms | 7 | AR 13,533 ms |
| c9c6baf0 | other-target | 13,381 ms | 12 | Views 8,943 ms; GC 3,772 ms |
| 4d6dff6c | observation-list | 12,671 ms | 2 | Reported AR 19,660 ms exceeds wall time; these figures cannot be added or treated as independent server execution times |
| 52a82011 | other-target-with-farmer | 9,540 ms | 14 | Views 7,746 ms; GC 3,047 ms |

Callsite-by-callsite review

| Logged modules_controller.rb line | Actual path at baseline | Change / finding |
| --- | --- | --- |
| 12109, 12114 | jeevika_jankar_bill_rows; canonical-month and permissive fallback target reads | Missing summaries were omitted from the batch cache. Each bill then recalculated its missing result. Cache nil results after a batched fallback, preserving saved-item/saved-total behavior. Mixed canonical/numeric-month owners still match individual calculation; mapped/JJ login paths remain unchanged. |
| 14781 | build_training_target_mappings | Previously read every scoped target's full serialized farmer list and preloaded owners before filtering. Read id/activity headers with pluck, apply the same Ruby precedence and saved-target exception, then load eligible targets in the original DB order and preload only their owners. One extra lightweight query trades for fewer large rows; full selected target payloads are retained. |
| 8525, 8515 | dashboard_target_mappings and owner preload | Resolving training references could trigger the entire global dashboard target list even on a payment page. Reuse the dashboard index only when already loaded; otherwise batch only referenced IDs. Missing references remain cached; lookup results and the existing out-of-visible-scope reference fallback are preserved. |
| 2702 | dashboard_training_form_records_by_month | This is a full monthly training record read/countability filter, not one query per individual target. It can also trigger reference preloading. Removed the unrelated global mapping load from that dependency. Full training data remains available for evidence/attachment consumers; no photo fields or completion rules were removed. Production query-plan/row-size verification is still needed for the raw monthly scan. |
| 12585 | month_master_month_options / lazy master relation | Materialize the request-local active month rows once. This callsite can include first-use schema metadata reads, so the old trace count does not equal the completed-request application query count. New trace metadata distinguishes schema/application and async work. |
| 11430 | jeevika_bill_approval_history_by_bill_id | An explicitly empty visible-bill list previously dropped the filter and loaded every history. It now returns an empty scope. A later behavior rescan removed the inferred form-record history filter; unrelated form state must not filter the bill actually requested. History order and approval interpretation remain unchanged. Existing bill-id partial index already exists. |
| 9395 | preload_vrp_lookup_values! | Already restricts references and omits signature data. The unnecessary global target dependency was the additional broad-load path removed above. No identity precedence change. |
| 10662 | passbook attachment preloader | Skip associations already loaded, including missing attachments and loaded blobs. Existing first-load batching remains. |
| 15571, 15590 | staff dropdown sources | Reuse narrow, ordered User and module-user catalogues across role-pattern dropdowns instead of repeatedly instantiating complete user/profile/password/upload records. Ruby role matching and labels remain. |

Rendering/GC follow-up for GP, training and other-target forms

- Cache the serialized location browser payload under its live catalogue revision, avoiding repeated deep duplication and JSON construction on warm form renders. HTML escaping still occurs through the original json_escape helper; the JSON contents are unchanged.
- Fixed location_catalogue_revision returning a digest on first use but its raw source array on subsequent calls. A stable digest now keeps cache keys consistent in the same render.
- Source changes, deletes, and direct writes without timestamp updates still invalidate the browser payload. Regression tests cover this.
- No arbitrary list cap, default-filter change, hidden selected farmer, background recalculation or delayed eligibility result was introduced.

Measured local results

Rollback-only synthetic benchmark in jj_feature_removal_test_20261026, comparing against 7dbf517. Schema metadata was warmed equally and SQL query caching was disabled for both runs. These are local measurements, not production response-time predictions.

| Fixture | Before | After | Parity |
| --- | --- | --- | --- |
| 30 bills without live target summaries | 98 SELECTs; 88.04 ms; 34,405 allocations | 8 SELECTs; 14.63 ms; 4,190 allocations | Identical displayed target/achievement totals |
| 100 target rows, 2,000 farmer IDs each; 10 eligible | 100 instantiated targets; 12.34 ms; 1 query | 10 instantiated targets; 7.02 ms; 2 queries | Identical selected IDs, order and farmer arrays |

The second benchmark measures the target selection read, not the complete training HTTP render. Times vary between runs.

Validation

- Final focused suite: 94 tests, 654 assertions, 0 failures/errors. Covers payment totals and legacy fallbacks, request scopes, training visibility integration, target payload/order, owner loading, observation filtering, cache invalidation, GP/VRP option lookups, target-mapping option readers, dashboard and safe trace formatting.
- Additional billing/approval/invoice/attachment workflow suite: 61 tests, 233 assertions passed. Existing passbook query-count test: 1 test, 7 assertions passed. Combined successful runs: 156 tests, 894 assertions.
- Expanded audit initially ran 90 tests and encountered 1 failure plus 4 errors in older visibility/API tests. The same five failures reproduced with the unchanged baseline controller: tests without request/params, an outdated SQL-bind capture helper, and a visibility expectation. Business visibility rules were not changed to make those tests pass.
- Ruby/Python syntax and git diff --check passed. No production data, schema, services or deployment settings were changed.

Reproduction

    python3 script/analyze_request_performance.py /path/to/journal.txt
    RAILS_ENV=test DATABASE_URL=<isolated-test-db> PERFORMANCE_BASELINE_REF=7dbf517 bin/rails runner script/benchmark_log_hotspots.rb

The benchmark refuses production/development and requires the explicitly named isolated test database prefixes. Its fixtures roll back.

Remaining production verification

The excerpt contains many 0.8–1.8 second reads and concurrent long renders in the same Puma process. CPU/GVL pressure, schema warmup, pool waits, database I/O, locks and temp-file sorts cannot be distinguished from this log alone. The existing script/performance_runtime_snapshot.sh collects memory/CPU, active DB waits, blockers and temp-file counters while reproducing a request. New PERFORMANCE_SQL entries label schema/application and async work without SQL text, query names, binds or credentials.

After deployment, compare the same user/month/scope on cold and warm visits and inspect query plans for any remaining monthly training/history/target reads. The 156-second request had only 28 queries, so reducing the separate 405-query case does not prove that the 156-second case is resolved. Generic full-list rendering and complete exports remain potentially expensive; arbitrary-scale latency and a production speedup have not been verified.
