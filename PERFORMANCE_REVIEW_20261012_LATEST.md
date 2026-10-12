# Latest performance and participation review — 12 October 2026

All 545 lines of the new attachment were processed and matched by request ID. Journal request timestamps are UTC (10:30 corresponds to 16:00 India time). Routes below omit query strings and personal form values. 110 completed requests have matching Started lines.

## Corrected request timings

| Route | Requests | Min–max seconds | Worst request DB seconds | Queries | Status |
| --- | ---: | ---: | ---: | ---: | ---: |
| `GET /modules/jeevika-jankar-bill-list` | 7 | 55.450–252.161 | 185.541 | 211 | 200 |
| `GET /modules/other-target-with-farmer` | 3 | 98.424–231.710 | 225.078 | 19 | 200 |
| `GET /modules/jeevika-jankar-bill-process` | 4 | 52.049–168.599 | 109.521 | 26 | 200 |
| `GET /vrps` | 7 | 0.384–125.660 | 121.930 | 43 | 200 |
| `GET /vrps/:id/edit` | 3 | 16.528–118.131 | 104.980 | 52 | 200 |
| `GET /modules/training-form` | 5 | 1.644–111.211 | 56.161 | 29 | 200 |
| `GET /vrps/new` | 7 | 15.639–99.968 | 87.670 | 31 | 200 |
| `GET /modules/other-target` | 4 | 17.825–98.503 | 99.847 | 16 | 200 |
| `GET /dashboard/farmer-participation-report` | 1 | 95.783–95.783 | 93.398 | 11 | 200 |
| `POST /vrps` | 2 | 36.859–94.157 | 82.642 | 35 | 422 |
| `GET /modules/jeevika-jankar-payment-list` | 1 | 47.009–47.009 | 8.565 | 72 | 200 |
| `GET /modules/jeevika-jankar-observation-list` | 6 | 3.033–45.959 | 45.746 | 17 | 200 |
| `GET /dashboard` | 10 | 5.220–30.698 | 24.660 | 93 | 200 |
| `GET /modules/training-form/training_target_farmers` | 1 | 19.459–19.459 | 8.964 | 38 | 200 |
| `PATCH /vrps/56` | 1 | 18.638–18.638 | 8.951 | 50 | 302 |
| `GET /modules/training-form-list` | 5 | 1.328–12.779 | 11.912 | 9 | 200 |
| `GET /modules/add-vrp-type` | 1 | 8.369–8.369 | 8.148 | 4 | 200 |
| `GET /users/new` | 1 | 6.172–6.172 | 3.672 | 6 | 200 |
| `GET /modules/other-target-with-farmer-list` | 2 | 0.338–4.188 | 4.069 | 5 | 200 |
| `GET /modules/parent-office-add` | 1 | 4.097–4.097 | 4.045 | 10 | 200 |
| `GET /modules/office-category-add` | 1 | 4.064–4.064 | 4.002 | 8 | 200 |
| `GET /modules/office-list` | 1 | 3.956–3.956 | 0.562 | 5 | 200 |
| `GET /modules/office-mapping-add` | 1 | 3.942–3.942 | 3.845 | 9 | 200 |
| `GET /target_mappings` | 2 | 0.167–3.270 | 0.085 | 25 | 200 |
| `GET /modules/jeevika-jankar-transfer-list` | 1 | 2.805–2.805 | 2.779 | 8 | 200 |
| `POST /modules/training-form/records` | 1 | 2.293–2.293 | 1.018 | 13 | 302 |
| `GET /modules/user-hierarchy-list` | 1 | 1.702–1.702 | 0.028 | 7 | 200 |
| `GET /modules/access-control-list` | 2 | 0.054–1.047 | 0.976 | 5 | 200 |
| `GET /modules/add-activity-group` | 1 | 0.925–0.925 | 0.878 | 7 | 200 |
| `POST /login` | 4 | 0.010–0.637 | 0.619 | 3 | 302 |
| `GET /modules/other-target-list` | 5 | 0.080–0.635 | 0.570 | 5 | 200 |
| `GET /modules/jeevika-jankar-transfer` | 1 | 0.312–0.312 | 0.234 | 9 | 200 |
| `GET /modules/access-control` | 2 | 0.100–0.126 | 0.061 | 13 | 200 |
| `GET /modules/add-vrp-activity` | 1 | 0.117–0.117 | 0.040 | 6 | 200 |
| `GET /asa360-mapping` | 1 | 0.096–0.096 | 0.032 | 5 | 200 |
| `GET /modules/user-hierarchy-mapping` | 1 | 0.095–0.095 | 0.031 | 7 | 200 |
| `GET /afls` | 1 | 0.064–0.064 | 0.017 | 7 | 200 |
| `GET /modules/vrp-activity-list` | 1 | 0.047–0.047 | 0.015 | 5 | 200 |
| `GET /login` | 4 | 0.013–0.033 | 0.014 | 3 | 200 |
| `GET /modules/activity-group-list` | 1 | 0.031–0.031 | 0.006 | 5 | 200 |
| `GET /` | 2 | 0.007–0.009 | 0.004 | 0 | 302 |
| `GET /logout` | 3 | 0.003–0.008 | 0.000 | 0 | 302 |

The 231.7-second request is Other Target With Farmer, not Payment List. The worst Bill List request is 252.2 seconds. The 118.1-second request is VRP Edit, not New. The screenshot shows nginx **504 Gateway Time-out**; Rails later completing a request with 200 does not mean the browser received that result before the proxy timed out.

Login GET is 13–33 ms and login POST 10–637 ms in this attachment. Dashboard is 5.220–30.698 seconds. The final login POST completed in 10 ms, followed by a 5.220-second dashboard request. The slow dashboard redirect can therefore look like slow login. The blue Turbo progress bar cannot identify the underlying SQL query or wait by itself.

All reported slow web requests come from the same Puma PID, with overlap and large GC intervals. ActiveRecord time includes more than isolated PostgreSQL execution and sometimes exceeds wall time. No SQL statements, query plans, lock snapshots, nginx upstream timings or browser resource timing entries are present, so indexes cannot be called the sole proven cause.

## Farmer Training Participation Status

Reference read: `/home/papl/VRP/app/controllers/modules_controller.rb`, its participation queries and `test/controllers/dashboard_sql_projection_test.rb`. Preserved definitions: red = no countable training in the selected period, yellow = one distinct training record, green = more than one distinct training record; All Months removes month/week predicates. Existing JJ/CC/office authorization and rejected/returned/inactive/deleted/pending-edit exclusions remain in place.

Targeted report corrections:
- All FCO now retains the entire already-authorized farmer population, including missing office IDs; selected FCOs can match saved office-name aliases.
- Mapped Farmer counts unique, nonblank farmer IDs across target/office aliases instead of summing the same farmer more than once.
- Mapped and pending detail joins use the farmer ID across legacy office-ID aliases after authorization scopes are injected. A missing/alternate office ID no longer hides a genuinely mapped farmer.
- Yellow detail counts distinct training records, matching the card when a saved farmer ID occurs twice in one record.
- Specific months with no training leave farmers pending; they do not silently zero every box. Report cache keys were versioned.

The mapped population and registered-farmer population are different: mapped counts target assignments, while red/yellow/green classify registered visible farmers as in the reference. These totals must not be interpreted as identical denominators. The requested report correction is the functional change; billing/approval logic was not replaced with VRP business rules.

## Performance changes

- Ported VRP lightweight bill list reads, retaining every summary/status/identity field while omitting unused nested farmer_details. The final query parses each JSON document once. Full detail, print and downloads load the original bill.
- Ported monthly live-total batching for ordinary numeric JJ bill owners. Missing canonical-month totals, legacy labels and mapped/JJ login scopes retain the original individual fallback path. No stored total replaces a live total.
- Bill Process duplicate checks project only the seven fields used by the existing rejection/deletion/state rules, without reading bill evidence into Ruby.
- Bill Process achievement-key cache fills are coalesced for simultaneous requests using the existing cache key and TTL.
- Dashboard JJ rows, target associations and shared module JJ lookup omit unused agreement signature data. Bank/profile/identity fields and existing scopes remain available.
- Observation uses the same lightweight bill projection.
- Three concurrent non-unique indexes support normalized AFL office IDs/names and module slug/month predicates. Migration applied in the isolated test database.
- VRP attachment thumbnails now use lazy loading and asynchronous image decoding; invoice/print images retain their existing loading behavior.

## Isolated synthetic benchmark

25 numeric JJ bills in one month, with 500 nested farmer details per saved bill. Dedicated PostgreSQL test database; all records rolled back. JSON deserialization is included. Output equality is asserted. These are workload measurements, not production response SLAs.

| Workload | Before ms | After ms | SELECTs before → after | Allocations before → after |
| --- | ---: | ---: | ---: | ---: |
| bill_payload_25_bills_500_farmer_details_each | 45.53 | 40.98 | 1 → 1 | 38,801 → 972 |
| live_bill_totals_25_jjs_one_month | 138.96 | 29.08 | 57 → 2 | 44,622 → 12,315 |

Bill JSON read into Ruby decreased from 13,088,900 bytes to 3,675 bytes. Reproduce with `RAILS_ENV=test bin/rails runner script/bill_read_benchmark.rb` using a dedicated test database.

## Image timing and production validation

The journal contains no image or Active Storage GET timings. Uploaded JPEG filenames in POST parameters are not image-download timing measurements. Browser image durations, sizes, DNS/TLS, upstream waits and current deployment status cannot be inferred from this log. Static images may be served directly by nginx. No production server/database was modified.

After the reviewed files are deployed, run `RAILS_ENV=production bin/rails db:migrate` in the normal deployment environment. During a slow request, run `PERFORMANCE_DIAGNOSTICS.sql` on the application database; it checks active waits/blockers, table statistics and actual index valid/ready flags. Check the deployed Puma worker/thread settings and nginx request/upstream timing before changing capacity or timeouts.

For scalar report diagnostics use `RAILS_ENV=production MONTH=October bin/rails runner script/diagnose_farmer_participation.rb`, optionally with `FCO` and `USER_ID`. It reports the visible farmer population, missing office IDs and training field types without dumping farmer records. Browser Network timing or nginx access records with request/upstream durations are needed to measure images and the observed gateway timeout.

Every production API running in milliseconds is not established by these changes; exports, upstream APIs, proxy/network delay and remaining mapped-owner fallback reads need production measurement.

## Validation

- Committed baseline in an isolated /tmp copy: 323 Rails tests, 2,117 assertions, 19 failures and 6 errors.
- Final implementation full suite: 332 tests, 2,162 assertions, the identical 25 failure/error names. No new failures/errors.
- Final focused report, billing, scope, attachments and lookup suite: 63 tests, 411 assertions, zero failures/errors. Billing parity includes actual assigned farmers and completed training, plus numeric-month fallback and mapped-login guards.
- New participation tests cover All FCO, a missing office ID, selected-office name aliases, All Months, no-entry months, repeated IDs within one training record, cross-office-ID mapped deduplication, dashboard association preloading and unauthorized scope.
- JavaScript: 9/10 test files pass. The unchanged language-switch test file retains its existing four document.getElementById stub failures; the same failure was established on the prior staged baseline.
- New concurrent indexes applied successfully in the isolated PostgreSQL test database; schema updated. Ruby/JavaScript syntax and git diff --check passed.

The existing full-suite failures include dashboard/access expectations, request/session mocks, training uploads/visibility, agreement archives, a query-count assertion and the two OTP tests referencing missing Minitest::Mock. They were not hidden or resolved by changing unrelated business rules.
