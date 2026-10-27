Full performance/behavior rescan — 26 October 2026

Result

Reviewed the complete uncommitted performance diff against 7dbf517. All 19 audited pages returned HTTP 200 on one cold and three warm visits. Across all 76 baseline/current comparisons, visible text, form control values/options, and browser data-* payloads matched exactly. Three non-empty Excel exports also matched headers and worksheet contents on cold/warm visits (6 comparisons, 20 records plus header per export).

This is 82 output comparisons across 164 HTTP requests, using identical deterministic fixtures and a frozen application date in an isolated test database. It is not a production latency guarantee or a browser frame-rate measurement.

Additional corrections from this review

- Preserve nested legacy staff-name JSON key order with json_build_object/data::json. Projection using jsonb could reorder nested keys and change the rendered legacy label; a regression test now covers this.
- Remove the inferred approval-history filter based on @record/@bill_detail_record. An unrelated form record must not hide histories for the bill actually requested. Keep the safe explicit-empty visible-bill scope optimization.
- Reuse targets and owners already loaded by the bill calculator during training reference resolution, avoiding redundant ID fetches. A query-count regression covers reuse.
- The first GP comparison had rows with identical created_at values and an undefined database tie order. Added distinct deterministic fixture timestamps, without changing application sorting. Focused and full repeat comparisons then matched.

Full page observations

Sequential isolated fixtures: 20 JJs, 200 farmers, 60 targets, 20 training entries, 20 approved bills, 200 GPs and 200 villages. External HTTP was disabled so synthetic data could not reach external services. Fixtures rolled back; development and production were untouched. Timing is the median of three warm visits. Small differences are not statistically established speedups or regressions; source/header filtering intentionally adds one lightweight query to avoid large target payloads.

| Page | Baseline warm median ms | Current warm median ms | Current queries | Output parity |
| --- | ---: | ---: | ---: | --- |
| /modules/jeevika-jankar-payment-list | 76.95 | 75.15 | 23 | Exact |
| /modules/training-form | 38.42 | 41.80 | 18 | Exact |
| /modules/jeevika-jankar-observation-list | 24.40 | 29.07 | 8 | Exact |
| /modules/jeevika-jankar-payment-list-detail | 25.23 | 27.95 | 9 | Exact |
| /modules/other-target | 29.52 | 30.38 | 12 | Exact |
| /modules/other-target-with-farmer | 31.28 | 31.35 | 13 | Exact |
| /modules/gram-panchayat-master | 76.47 | 71.46 | 8 | Exact |
| /modules/jeevika-jankar-bill-list | 84.73 | 88.74 | 25 | Exact |
| /modules/jeevika-jankar-bill-process | 20.10 | 22.00 | 11 | Exact |
| /modules/other-target-list | 12.45 | 11.87 | 5 | Exact |
| /modules/other-target-with-farmer-list | 14.23 | 11.36 | 5 | Exact |
| /modules/access-control-list | 13.87 | 10.91 | 5 | Exact |
| /modules/approval-master | 16.92 | 13.17 | 6 | Exact |
| /modules/user-hierarchy-mapping | 16.59 | 16.70 | 7 | Exact |
| /modules/training-form-list | 69.13 | 54.83 | 10 | Exact |
| /dashboard | 155.22 | 141.27 | 39 | Exact |
| /target_mappings/list | 45.05 | 46.32 | 10 | Exact |
| /vrps/new | 62.84 | 68.42 | 21 | Exact |
| /vrps/approvals | 18.91 | 20.48 | 9 | Exact |

Verification

- Combined Rails behavior/performance/workflow suite: 158 tests, 891 assertions, zero failures/errors. Includes role visibility integrations, live/saved bill totals, numeric-month fallback, approval/resubmission, invoice/attachment logic, target ordering, cache invalidation, JSON key order and unrelated form-history context.
- Relevant JavaScript suite: 10 test files passed (bill loading, location options, target data/rendering/submission, pagination, transfer filtering and dashboard export).
- The earlier expanded audit's five failures were reproduced against unchanged baseline code; this rescan does not claim the entire historical repository suite is green. The known language-switch test mock problem is outside these changed paths.
- Ruby syntax and git diff --check passed.
- Request allocation/GC counters in rescan_slow_pages.rb are captured immediately after HTTP completion, excluding DOM/hash verification work.

Reproduce

    RAILS_ENV=test DATABASE_URL=<isolated-test-db> RESCAN_PASSES=4 bin/rails runner script/rescan_slow_pages.rb
    RAILS_ENV=test DATABASE_URL=<isolated-test-db> RESCAN_BASELINE_REF=7dbf517 RESCAN_PASSES=4 bin/rails runner script/rescan_slow_pages.rb
    RAILS_ENV=test DATABASE_URL=<isolated-test-db> RESCAN_EXPORTS=1 bin/rails runner script/rescan_slow_pages.rb

The runner requires an isolated database name beginning jj_feature_removal_test_ or jj_performance_test_. RESCAN_PATHS can restrict the audit to selected paths; RESCAN_DETAIL=1 includes synthetic visible text for diagnosing differences. It does not change application code or enable new export formats.

Are all production issues fixed?

Not verified. The application-level redundant reads and tested behavior regressions are addressed. All listed pages render successfully under this fixture, but this fixture cannot reproduce production volume, concurrent GC/GVL pressure, database waits, upstream latency or browser rendering cost. The 156-second request had 28 SQL queries, whereas the 405-query request was a different request. Passing the missing-summary benchmark does not prove the 156-second case is gone.

Remaining verification requires fresh production logs for the same user/month/scope, cold/warm visits and runtime wait/memory metrics. The raw monthly training read can still process a large month's data. Existing script/performance_runtime_snapshot.sh captures DB waits, blockers, CPU/memory and temporary-file counters. No arbitrary pagination cap, hidden rows, changed default filter or weaker permission rule was introduced to obtain faster results.

Follow-up: see PERFORMANCE_MONTHLY_READ_REVIEW_20261027.md for the snapshot-preserving monthly-read optimization and the latest 164-test verification.
