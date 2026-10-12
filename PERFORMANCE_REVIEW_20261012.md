# Performance review — 12 October 2026

All 352 attachment lines were read and correlated by request ID. 70 completed requests have a route; 5 request IDs have no completion in this partial log. SQL statements and plans are absent.

| Route | Requests | Min–max seconds | Worst request DB seconds | Queries | GC seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| `GET /modules/other-target` | 1 | 171.397–171.397 | 161.467 | 16 | 11.709 |
| `GET /modules/jeevika-jankar-bill-list` | 2 | 101.610–153.612 | 92.974 | 211 | 10.872 |
| `GET /modules/jeevika-jankar-payment-list` | 3 | 48.297–134.681 | 102.058 | 72 | 9.803 |
| `GET /modules/training-form` | 1 | 108.487–108.487 | 55.440 | 29 | 6.492 |
| `GET /vrps` | 3 | 1.921–76.065 | 75.793 | 14 | 5.979 |
| `GET /vrps/new` | 2 | 66.344–68.679 | 58.878 | 36 | 10.758 |
| `GET /modules/jeevika-jankar-bill-process` | 1 | 51.716–51.716 | 1.988 | 26 | 2.732 |
| `GET /dashboard` | 3 | 4.501–50.559 | 46.656 | 92 | 6.498 |
| `GET /modules/jeevika-jankar-payment-list-detail` | 2 | 1.288–48.825 | 56.072 | 15 | 1.964 |
| `GET /modules/training-form/training_target_farmers` | 1 | 48.107–48.107 | 42.884 | 30 | 5.838 |
| `GET /dashboard/farmer-participation-report` | 1 | 41.710–41.710 | 39.762 | 11 | 3.995 |
| `GET /modules/user-hierarchy-list` | 10 | 0.846–39.501 | 36.487 | 7 | 3.805 |
| `GET /modules/jeevika-jankar-transfer` | 8 | 0.082–31.540 | 31.486 | 9 | 1.842 |
| `GET /target_mappings` | 1 | 22.139–22.139 | 16.035 | 14 | 3.163 |
| `GET /modules/jeevika-jankar-observation-list` | 3 | 0.081–13.281 | 13.126 | 10 | 0.834 |
| `GET /users/new` | 2 | 1.612–11.800 | 0.232 | 9 | 2.397 |
| `GET /modules/user-hierarchy-mapping/records/178560/edit` | 1 | 9.622–9.622 | 9.475 | 8 | 0.321 |
| `GET /users` | 2 | 0.072–8.814 | 4.303 | 6 | 1.705 |
| `GET /modules/jeevika-jankar-completed-payment-list` | 2 | 1.183–7.646 | 7.519 | 7 | 0.284 |
| `GET /modules/training-form-list` | 2 | 1.880–6.414 | 6.040 | 6 | 0.589 |
| `GET /modules/add-activity-group` | 1 | 2.063–2.063 | 2.015 | 7 | 0.726 |
| `GET /modules/user-hierarchy-mapping` | 4 | 0.056–0.676 | 0.610 | 7 | 0.079 |
| `GET /afls` | 1 | 0.524–0.524 | 0.485 | 7 | 0.081 |
| `GET /modules/jeevika-jankar-transfer-list` | 4 | 0.021–0.194 | 0.166 | 5 | 0.009 |
| `GET /modules/access-control` | 1 | 0.168–0.168 | 0.099 | 13 | 0.011 |
| `GET /modules/other-target-list` | 1 | 0.149–0.149 | 0.074 | 5 | 0.009 |
| `PATCH /modules/user-hierarchy-mapping/records/178560` | 1 | 0.084–0.084 | 0.073 | 2 | 0.004 |
| `GET /modules/add-vrp-activity` | 1 | 0.076–0.076 | 0.012 | 6 | 0.001 |
| `GET /modules/activity-group-list` | 1 | 0.039–0.039 | 0.019 | 5 | 0.001 |
| `GET /modules/vrp-activity-list` | 1 | 0.032–0.032 | 0.007 | 5 | 0.001 |
| `GET /modules/access-control-list` | 1 | 0.031–0.031 | 0.008 | 5 | 0.000 |
| `GET /` | 2 | 0.005–0.010 | 0.006 | 0 | 0.000 |

## Findings and limits

The largest completed request is **Other Target**, not Transfer. The earlier pasted timing table mixed route names; this report uses the request ID on each Started/Completed line. The same routes vary sharply: Transfer is 82 ms–31.54 s, VRP list 1.921–76.065 s, hierarchy 0.846–39.501 s. Slow overlapping requests in this attachment all come from the same Puma PID. Some DB timings exceed wall time and one Views time is negative, so these counters are not enough to isolate database execution, Ruby scheduling, or connection waits. GC overlaps other timings; do not add it to total duration.

The supplied memory snapshot shows 5 GiB available and no swap used. It does not establish a RAM shortage during the slow requests. The PostgreSQL snapshot was taken after the slow period and does not establish the waits during that period. The attachment does not show a completed unauthenticated login page request; it cannot explain browser DNS/TLS or upstream queuing delays.

## Read optimizations

- Transfer, approved-JJ bill dropdown and hierarchy cluster rows select only the attributes they display, avoiding signature and unrelated profile payloads.
- Observation loads bills once and batches creator identities before visibility checks instead of loading, checking and sorting the same bills twice.
- Bill approval channel ordering is reused within the request. Channel matching, per-level priority and tie ordering are preserved.
- Bill identity membership uses a Set instead of repeatedly searching an array.
- Existing client pagination keeps full-list search, filters and exports, uses Set membership, and skips unchanged hidden-property writes. Empty-row detection uses textContent to avoid repeated layout-dependent innerText reads.
- Plain hierarchy role checks reuse the registration user catalogue, removing one repeated user SELECT per plain label.
- Four concurrent, non-unique indexes support dashboard source-revision timestamps on afls, vrps and module_records, plus module_slug/updated_at on module_records. Existing JSON, login, owner/month and bill-history indexes remain in place. COUNT(*) cache revision checks still run; these indexes target MAX(updated_at).

Client pagination still sends all rows to the browser. Server pagination would require moving the existing full-list search, column filters, exports and bulk selection together; it was not silently introduced. These changes do not establish that every production page is now fast.

## Isolated before/after benchmark

Synthetic records in a dedicated PostgreSQL test database, transaction rolled back. Output equality is checked, not assumed. These are individual workload timings, not production page timings.

| Workload | Before ms | After ms | Allocations before → after |
| --- | ---: | ---: | ---: |
| transfer_500_jjs_with_64kb_signatures | 74.84 | 5.21 | 40,019 → 8,792 |
| approval_channels_500_bills_120_steps | 200.5 | 33.98 | 622,586 → 88,696 |

The transfer benchmark omits 32,768,000 bytes of signature data without changing option labels. Reproduce with `RAILS_ENV=test bin/rails runner script/jj_read_benchmark.rb` against a dedicated test database. The migration was applied successfully in the isolated database. PostgreSQL chose an Index Only Scan for the VRP MAX(updated_at) query; it preferred sequential scans for the tiny AFL/module fixture tables. Production query plans have not been captured.

## Requested CC registration fix

The Petlawad scenario is reproduced with a hierarchy label `Pritesh Jain (Cluster Incharge)` and separate same-name FCO and CC accounts. Previously the first matching registered user could be the FCO account, giving the CC option the wrong FCO/TO metadata and causing the browser's office filter to remove it. Registration enrichment now prefers the matching Active Cluster Incharge account. Its displayed Office Name takes precedence over a stale hidden office_category. Existing hierarchy scope, exact name matching and browser FCO/TO filters are retained. This is the explicitly requested functional fix; it is separate from the performance-only changes.

## Deployment and production measurement

No production database or server was changed. After deploying the reviewed application files, apply migrations with `RAILS_ENV=production bin/rails db:migrate` using the deployment's normal Ruby/Bundler environment. Concurrent index builds add no uniqueness rules and do not rewrite application records; they still consume database resources while building.

Capture `PERFORMANCE_DIAGNOSTICS.sql` on the production application database while a slow request is active, including index valid/ready flags and waits. Match the next request logs by request ID. Check the deployed Puma worker/thread configuration and upstream request timings before changing concurrency. This workspace has no live server access, so no production response-time guarantee or complete scalability claim is made.

## Validation

- Original staged application baseline (separate /tmp copy): 315 Rails tests, 2,080 assertions, 19 failures and 6 errors.
- Performance changes before the requested CC fix: 318 tests, 2,089 assertions, the identical 25 failure/error names.
- Full suite with CC registration/form regressions: 322 tests, 2,104 assertions, the identical 19 failures and 6 errors. No new failure/error names.
- Final focused hierarchy, registration, lookup and performance suite (including the added plain-label N+1 assertion): 28 tests, 126 assertions, zero failures/errors. The repeated plain-label checks plus enrichment execute one User SELECT.
- JavaScript: 9 of 10 test files pass, including full-list pagination/search/filter behavior. The language-switch test file has the same four `document.getElementById is not a function` stub failures in the original staged application; it was not changed.
- CC regression before the fix: same-name FCO selection and stale-category tests both failed. After the fix the unit cases and the real `/vrps/new` hierarchy-to-form metadata case pass.
- Index migration applied successfully to the isolated test database; schema updated. Ruby and JavaScript syntax and `git diff --check` passed.

The original failures concern existing dashboard/access expectations, training visibility/upload tests, an agreement archive assertion, missing request/session mocks, OTP `Minitest::Mock`, and one FCO query-count assertion. They were not resolved by changing existing business rules in this performance task.
