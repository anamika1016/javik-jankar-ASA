# Performance audit — 12 November 2026

Follow-up: see [final rescan](performance-final-rescan-2026-11-13.md). The three previously tracked performance-test issues have now been investigated: the full-vs-fast Other Activity total discrepancy is fixed; two test fixtures were corrected without changing permissions. Historical timings below describe the earlier revision.

## Scope and result

Scanned all 84 completed requests in the supplied journal attachment. Request times below are historical production server times, not browser load times. No production deployment was performed.

Changed plain-label cluster-role resolution in ModulesController, VrpsController and API VrpAccess. Each request now builds a normalized label index once, replacing repeated full user scans. Existing normalizers, role precedence, duplicate-name matching, and inclusion of inactive users are preserved. The index is not shared between requests. No data migration is required.

## Measured change

Synthetic CPU-only benchmark: 1,000 user objects and 1,000 queried labels. Original methods are loaded from HEAD; results must be identical. These are not full-page or production measurements.

| Lookup | Before | After | Allocations before → after |
|---|---:|---:|---:|
| ModulesController | 955.92 ms | 5.73 ms | 4,099,023 → 30,008 |
| VrpsController | 892.39 ms | 1.94 ms | 8,128,504 → 12,256 |

Reproduce with `RAILS_ENV=test bundle exec rails runner script/cluster_role_label_performance_audit.rb`.

## Validation

- Focused regression suite: 57 tests, 419 assertions, zero failures/errors (role index, VRP lookups, training routing, farmer rendering).
- New regression test compares indexed results with legacy matching, including duplicate names, inactive users, unknown labels, case/role suffixes, and role edits between requests. It also rejects repeat full user scans.
- Selected broader suite: 105 tests, 642 assertions; 2 failures and 1 error. Re-running original HEAD methods reproduces the same three issues: office FCO/TO scope expectation, bill achievement summary expectation, and a location cache test request stub missing filtered_parameters. These were left unchanged to avoid changing unrelated business behavior.
- Existing synthetic HTTP audit: 46 cold/warm renders, all HTTP 200; largest measured time 120.26 ms. Small local synthetic dataset, admin viewer; this is not a production latency promise.
- Separate render hashes match for 42/46 renders against HEAD. VRP list/approval hashes were unstable across repeated runs, including repeated unchanged-code runs; do not treat those hashes as proof of parity. The focused role matching tests provide the behavioral check for this change.
- Existing 8,000-village form audit passed its output equality assertions. Those form cache improvements already existed before this change.

## Remaining production work

The supplied logs show cold catalogue construction, large form payloads, external JJ catalogue latency, SQL latency, and Ruby/GC contention. Existing repository optimizations address several of these, but local synthetic timing cannot establish what code is deployed or reproduce production data/concurrency. Deploy the reviewed code, capture the same routes under realistic roles and load, and compare request time, stage time, allocation count, SQL time, payload size, and GC. A universal 5 ms browser load is not supported by these measurements.

## All supplied completed requests (slowest first)

| Log line | Path | Status | Total ms | SQL ms | Views ms | GC ms |
|---:|---|---:|---:|---:|---:|---:|
| 52 | `/modules/gram-panchayat-master` | 200 | 10528.0 | 1913.6 | 6918.6 | 2713.0 |
| 339 | `/users/new` | 200 | 8598.0 | 207.3 | 926.9 | 2516.0 |
| 47 | `/modules/district-master` | 200 | 8207.0 | 1445.5 | 6736.8 | 2002.8 |
| 239 | `/jj-mapped-farmers` | 200 | 7959.0 | 87.3 | 13.6 | 0.0 |
| 154 | `/users/new` | 200 | 7664.0 | 226.8 | 848.4 | 1909.5 |
| 194 | `/vrps/new` | 200 | 7412.0 | 1916.2 | 5093.1 | 1428.2 |
| 38 | `/modules/lg-directory-list` | 200 | 7337.0 | 1305.9 | 503.7 | 1357.2 |
| 71 | `/modules/village-master` | 200 | 6514.0 | 743.0 | 316.2 | 1375.9 |
| 222 | `/target_mappings` | 200 | 5376.0 | 110.8 | 1767.5 | 405.2 |
| 382 | `/modules/training-form-list` | 200 | 4891.0 | 1193.3 | 265.4 | 301.9 |
| 282 | `/modules/jeevika-jankar-bill-list` | 200 | 4739.0 | 547.5 | 4006.9 | 589.7 |
| 7 | `/dashboard` | 200 | 4455.0 | 2992.0 | 54.0 | 398.4 |
| 114 | `/modules/office-list` | 200 | 3912.0 | 2.4 | 15.2 | 24.5 |
| 57 | `/modules/block-master` | 200 | 3676.0 | 3458.1 | 177.4 | 819.0 |
| 365 | `/vrps/approvals` | 200 | 3466.0 | 27.9 | 17.1 | 893.7 |
| 361 | `/vrps` | 200 | 3462.0 | 73.5 | 13.5 | 793.9 |
| 76 | `/modules/stakeholder-master` | 200 | 3220.0 | 2353.6 | 17.9 | 1318.0 |
| 200 | `/vrps/approvals` | 200 | 2774.0 | 21.9 | 37.3 | 468.1 |
| 129 | `/modules/add-activity-group` | 200 | 2555.0 | 2488.7 | 59.8 | 21.5 |
| 403 | `/modules/jeevika-jankar-payment-list` | 200 | 2530.0 | 533.4 | 1424.0 | 270.2 |
| 294 | `/modules/jeevika-jankar-payment-list` | 200 | 2113.0 | 191.8 | 1279.1 | 257.7 |
| 26 | `/dashboard` | 200 | 1882.0 | 183.3 | 44.2 | 458.2 |
| 17 | `/dashboard` | 200 | 1865.0 | 251.9 | 39.1 | 295.8 |
| 224 | `/dashboard` | 200 | 1747.0 | 322.9 | 40.1 | 156.3 |
| 331 | `/dashboard` | 200 | 1695.0 | 198.1 | 34.8 | 208.4 |
| 244 | `/modules/training-form` | 200 | 1640.0 | 1170.2 | 467.7 | 45.4 |
| 397 | `/modules/jeevika-jankar-bill-list` | 200 | 1608.0 | 189.7 | 444.2 | 157.9 |
| 386 | `/modules/other-target-list` | 200 | 1414.0 | 49.7 | 20.7 | 80.4 |
| 250 | `/modules/training-form-list` | 200 | 1358.0 | 1026.4 | 300.7 | 60.1 |
| 234 | `/target_mappings/list` | 200 | 1223.0 | 35.8 | 851.9 | 133.6 |
| 61 | `/modules/month-master` | 200 | 1003.0 | 973.6 | 24.9 | 0.0 |
| 300 | `/modules/jeevika-jankar-payment-list-detail` | 200 | 873.0 | 75.4 | 270.4 | 149.2 |
| 34 | `/dashboard` | 200 | 751.0 | 444.0 | 39.8 | 28.1 |
| 357 | `/vrps/new` | 200 | 552.0 | 89.3 | 145.6 | 134.8 |
| 410 | `/modules/jeevika-jankar-completed-payment-list` | 200 | 535.0 | 36.5 | 486.9 | 98.1 |
| 267 | `/modules/other-target-with-farmer` | 200 | 527.0 | 101.9 | 405.4 | 87.8 |
| 214 | `/vrp-agreements` | 200 | 520.0 | 326.0 | 118.4 | 16.1 |
| 109 | `/modules/office-mapping-add` | 200 | 486.0 | 407.4 | 69.3 | 18.2 |
| 257 | `/modules/other-target` | 200 | 459.0 | 103.7 | 309.1 | 163.8 |
| 352 | `/users/115/edit` | 200 | 438.0 | 49.7 | 356.7 | 65.6 |
| 277 | `/modules/jeevika-jankar-bill-process` | 200 | 406.0 | 308.8 | 25.0 | 43.8 |
| 262 | `/modules/other-target-list` | 200 | 290.0 | 10.1 | 238.2 | 0.0 |
| 99 | `/modules/parent-office-add` | 200 | 267.0 | 222.3 | 40.0 | 3.3 |
| 92 | `/modules/role-name` | 200 | 258.0 | 212.2 | 40.5 | 0.0 |
| 104 | `/modules/office-category-add` | 200 | 230.0 | 188.8 | 35.3 | 3.5 |
| 84 | `/modules/stakeholder-role` | 200 | 227.0 | 184.5 | 36.7 | 2.8 |
| 179 | `/modules/access-control` | 200 | 158.0 | 104.3 | 52.0 | 0.0 |
| 272 | `/modules/other-target-with-farmer-list` | 200 | 147.0 | 21.3 | 101.9 | 0.0 |
| 140 | `/modules/add-vrp-activity` | 200 | 138.0 | 79.6 | 49.2 | 15.9 |
| 323 | `/farmer-news` | 200 | 135.0 | 21.9 | 85.8 | 16.9 |
| 169 | `/modules/jeevika-jankar-transfer` | 200 | 120.0 | 47.0 | 71.2 | 16.3 |
| 159 | `/modules/user-hierarchy-mapping` | 200 | 111.0 | 77.0 | 28.2 | 4.2 |
| 209 | `/modules/approval-list` | 200 | 110.0 | 12.6 | 74.6 | 13.6 |
| 42 | `/modules/state-master` | 200 | 109.0 | 61.4 | 34.8 | 2.6 |
| 311 | `/jj-quizzes` | 200 | 109.0 | 20.9 | 57.8 | 38.4 |
| 327 | `/farmer-videos` | 200 | 86.0 | 23.9 | 42.4 | 0.5 |
| 164 | `/modules/user-hierarchy-mapping` | 200 | 82.0 | 43.4 | 33.4 | 6.5 |
| 335 | `/users` | 200 | 69.0 | 30.3 | 36.3 | 1.8 |
| 204 | `/modules/approval-master` | 200 | 66.0 | 45.4 | 18.4 | 0.0 |
| 319 | `/farmer-app-logins` | 200 | 65.0 | 16.3 | 25.8 | 9.1 |
| 13 | `/` | 302 | 63.0 | 67.5 |  | 0.3 |
| 369 | `/vrp-agreements` | 200 | 63.0 | 13.3 | 15.4 | 4.1 |
| 378 | `/jj-mapped-farmers` | 200 | 60.0 | 15.3 | 17.3 | 3.4 |
| 306 | `/modules/jeevika-jankar-completed-payment-list` | 200 | 51.0 | 9.5 | 35.5 | 1.7 |
| 117 | `/asa360-mapping` | 200 | 48.0 | 9.7 | 19.7 | 8.0 |
| 344 | `/users` | 200 | 47.0 | 7.5 | 36.6 | 4.6 |
| 218 | `/afls` | 200 | 45.0 | 8.9 | 32.1 | 0.6 |
| 150 | `/users` | 200 | 44.0 | 14.6 | 27.2 | 0.0 |
| 124 | `/modules/project-master` | 200 | 42.0 | 3.6 | 31.6 | 9.0 |
| 373 | `/target_mappings/list` | 200 | 41.0 | 17.9 | 15.5 | 0.3 |
| 145 | `/modules/vrp-activity-list` | 200 | 40.0 | 3.6 | 26.5 | 7.4 |
| 184 | `/modules/access-control-list` | 200 | 39.0 | 2.9 | 29.4 | 11.8 |
| 230 | `/target_mappings/vrp_mappings` | 200 | 39.0 | 21.9 | 0.3 | 0.0 |
| 348 | `/users` | 200 | 39.0 | 6.8 | 30.1 | 1.0 |
| 289 | `/modules/jeevika-jankar-observation-list` | 200 | 32.0 | 7.5 | 16.4 | 7.3 |
| 174 | `/modules/jeevika-jankar-transfer-list` | 200 | 21.0 | 2.8 | 14.6 | 3.0 |
| 189 | `/modules/add-vrp-type` | 200 | 21.0 | 2.4 | 15.9 | 4.8 |
| 132 | `/modules/activity-group-list` | 200 | 20.0 | 3.2 | 13.3 | 0.0 |
| 315 | `/farmer360` | 200 | 19.0 | 2.6 | 13.2 | 0.1 |
| 419 | `/login` | 200 | 15.0 | 4.1 | 9.3 | 0.0 |
| 30 | `/` | 302 | 6.0 | 1.7 |  | 0.0 |
| 415 | `/logout` | 302 | 5.0 | 0.0 |  | 0.0 |
| 3 | `/` | 406 | 4.0 | 0.0 | 2.7 | 0.0 |
| 22 | `/` | 302 | 2.0 | 0.0 |  | 0.0 |

## Logged slow stages

Stage spans can overlap and process CPU/GC/allocation counters may include other threads; do not add them to request time.

| Stage | Samples | Total ms | Max ms | Log lines |
|---|---:|---:|---:|---|
| `module_records` | 12 | 24150.0 | 5821.4 | 60, 68, 81, 89, 254, 286, 297, 303, 390, 394, 400, 407 |
| `user.form_options` | 2 | 14372.6 | 7611.2 | 156, 341 |
| `external.jj_catalogue` | 1 | 7931.6 | 7931.6 | 241 |
| `location.directory_build` | 1 | 6491.5 | 6491.5 | 51 |
| `vrp.location_attribute` | 1 | 5764.7 | 5764.7 | 197 |
| `module_records.visibility` | 2 | 4746.6 | 3396.4 | 385, 393 |
| `external.office_list` | 1 | 3846.5 | 3846.5 | 121 |
| `module_records.load` | 3 | 3052.2 | 2241.5 | 80, 285, 406 |
