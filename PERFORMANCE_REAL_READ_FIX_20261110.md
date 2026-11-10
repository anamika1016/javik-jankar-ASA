# 10 November: training-list fix and real-data read profiling

## Follow-up behavior rescan

Found and fixed one request-snapshot edge: the new admin fast path could overwrite revision summaries already captured earlier in the request. If a snapshot already exists, the original list path now retains it. The regression reproduced Pending changing to Approved on the same controller before the guard and passes after it. Normal first-read admin requests retain SQL-first selection.

Latest focused suite: **136 tests / 2,952 assertions, zero failures/errors**. A separate final five-test admin suite also passes, covering original full-data/all-row behavior for JSON/XLSX reads and staff filtering before the existing cap. The ten earlier broad-suite baseline checks are still unresolved and were not declared passing. Diff checks pass.

Baseline: `f8ea467`. The supplied production log contains 94 completed request IDs (including one partial request at the start) and 11 slow-SQL markers. Status counts: {302: 6, 200: 88}. All entries were grouped by request ID and inspected. HTTP 302 redirects are present, so the statement that every request was HTTP 200 is not exact.

## Concrete training-list change

The admin HTML training list still loaded and instantiated every candidate training before selecting the displayed 100 rows. The new path ranks in PostgreSQL and loads only the selected complete training records. Ranking reads ID/timestamp and latest revision status; it does not project all candidate training JSON into Ruby.

The original rules are retained: only admin HTML reads with no `all` parameter use this path; staff visibility stays on the existing path; latest revision wins by ID; only exact `Pending` gets first priority; creation time is floored to seconds with nil treated as epoch; equal-time ordering uses descending ID. Deleted/status records are not newly filtered. Export/all reads retain their original paths. Full selected training attributes and trainer resolution are retained.

Selected revision summaries are captured in the same SQL snapshot as ranking, including full summary metadata but excluding the same before/proposed/evidence/history snapshots as the original summary reader. This retains request-local badge/order consistency when an approval decision is made after selection. No approval, deletion, payment or ownership rule was changed.

## Actual local data, not just generated fixtures

The repository's local development database was available. Aggregate-only inspection found 887 training rows (~1.86 MB JSON), 110 bill rows (~8.21 MB JSON), 2,097 LG-directory rows and 2,056 village rows. Individual records/names were not logged. Profiling ran inside a PostgreSQL `READ ONLY` transaction, with both implementations warmed before the fair comparison and a fresh controller for each measured read.

| Same real-data admin read | Before | After |
|---|---:|---:|
| Training list read, 100 full returned records | 19.02 ms | 4.21 ms |
| Allocated objects | 85,077 | 13,054 |

Complete returned training attributes matched. Earlier first-process readings were 97.09 ms versus 7.95 ms, but those include unequal initialization/cache warming; the table above is the fair warmed comparison. These are controller read timings, not full HTTP or production timings.

Local form measurements: user form payload 222.60 ms cold / 1.93 ms warm; JJ location attribute 174.26 ms cold / 1.09 ms warm, ~953 KB output. These local results do not reproduce the production 9-second form times and do not establish their cause. Production may have different data, allocation pressure, CPU/resource contention or external waits. Queue wait cannot be inferred from Rails controller duration alone.

## Phase diagnostics for remaining delays

Production now logs `PERFORMANCE_STAGE` for read stages taking at least 250 ms. `PERFORMANCE_STAGE_LOG_MS` adjusts the threshold; zero disables it. Development/test defaults to disabled. Covered phases: module-record load and visibility, total module records, bill-list preparation, user form options, JJ location attribute, LG directory construction, external office list and external JJ catalogue.

Entries include stage, wall duration, process CPU/GC/allocation deltas and result count or string byte count. They do not include record contents, parameters, SQL text, credentials or user identifiers. Rails' existing tagged request ID connects stages to requests. Process counters include overlapping Puma threads, so they are not exclusive per-request CPU/GC measurements. Logging failures preserve the original return value/exception.

## Verification

- Full audit: **222 tests / 3,664 assertions; 212 pass, six failures and four errors remain**. The ten failing/error test names match the earlier original-code baseline; no new failure was found.
- New admin-list tests cover full row parity, all status types, newer-ID/older-timestamp precedence, subsecond ties, leading-zero reference IDs, the existing 100 cap, `all=1`, summary readonly/attribute parity, and retained revision snapshots after a later decision.
- The model instantiation notification reports only the 100 queried training rows in the 140-candidate test. Small revision summary stand-ins are instantiated from the ranking statement's returned scalar attributes, not by loading every revision snapshot.
- Final focused admin/safe-logging tests pass after adding string-byte-count privacy coverage. Syntax and diff checks pass.

## Every supplied request

Timings are from the supplied production log before this patch. GC overlaps other timings. Query strings and client addresses are omitted.

| Line | Request | Status | Total ms | Views ms | SQL ms | GC ms |
|---:|---|---:|---:|---:|---:|---:|
| 3 | `Partial request` | 302 | 24 | — | 13.7 | 0.2 |
| 5 | `GET /dashboard` | 200 | 1889 | 17.8 | 1061.6 | 253.3 |
| 9 | `GET /dashboard` | 200 | 1484 | 27.8 | 762.6 | 167.1 |
| 13 | `GET /` | 200 | 4 | 3.3 | 0.0 | 0.0 |
| 17 | `POST /login` | 302 | 8 | — | 3.1 | 0.0 |
| 22 | `GET /dashboard` | 200 | 1264 | 58.8 | 568.7 | 217.6 |
| 26 | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 1634 | 1534.9 | 89.7 | 277.5 |
| 31 | `GET /logout` | 302 | 2 | — | 0.0 | 0.0 |
| 35 | `GET /login` | 200 | 10 | 5.9 | 2.6 | 0.0 |
| 39 | `GET /target_mappings` | 200 | 3550 | 82.1 | 104.7 | 31.6 |
| 43 | `GET /target_mappings/vrp_mappings` | 200 | 26 | 0.2 | 16.1 | 0.0 |
| 47 | `GET /` | 302 | 7 | — | 2.9 | 0.0 |
| 51 | `GET /dashboard` | 200 | 2644 | 43.8 | 553.1 | 605.7 |
| 55 | `GET /modules/lg-directory-list` | 200 | 12206 | 470.7 | 1899.4 | 2835.0 |
| 61 | `GET /logout` | 302 | 4 | — | 0.0 | 0.0 |
| 65 | `GET /login` | 200 | 10 | 8.4 | 0.0 | 0.0 |
| 69 | `GET /` | 200 | 5 | 4.0 | 0.0 | 0.0 |
| 73 | `GET /modules/state-master` | 200 | 80 | 14.4 | 54.9 | 0.0 |
| 78 | `GET /modules/district-master` | 200 | 7619 | 6050.7 | 1550.4 | 1805.1 |
| 84 | `GET /modules/block-master` | 200 | 311 | 118.3 | 153.5 | 54.9 |
| 89 | `GET /modules/gram-panchayat-master` | 200 | 1551 | 172.7 | 188.2 | 391.1 |
| 94 | `GET /modules/village-master` | 200 | 13071 | 6335.1 | 1551.8 | 3215.4 |
| 100 | `GET /modules/month-master` | 200 | 935 | 25.7 | 905.4 | 3.5 |
| 105 | `GET /modules/stakeholder-master` | 200 | 19 | 12.6 | 1.7 | 2.6 |
| 110 | `GET /modules/stakeholder-role` | 200 | 190 | 28.5 | 157.4 | 2.5 |
| 115 | `GET /modules/role-name` | 200 | 169 | 36.3 | 126.8 | 5.9 |
| 120 | `GET /modules/parent-office-add` | 200 | 345 | 34.5 | 307.3 | 0.0 |
| 125 | `GET /modules/office-category-add` | 200 | 245 | 28.3 | 211.3 | 0.0 |
| 130 | `GET /modules/office-mapping-add` | 200 | 314 | 34.6 | 273.1 | 0.0 |
| 135 | `GET /modules/office-list` | 200 | 3597 | 15.6 | 1.7 | 12.6 |
| 140 | `GET /asa360-mapping` | 200 | 30 | 11.1 | 8.2 | 1.1 |
| 144 | `GET /modules/project-master` | 200 | 29 | 19.2 | 2.7 | 2.6 |
| 149 | `GET /modules/add-activity-group` | 200 | 3208 | 36.8 | 3167.6 | 4.2 |
| 155 | `GET /modules/activity-group-list` | 200 | 24 | 13.5 | 5.2 | 1.8 |
| 160 | `GET /modules/add-vrp-activity` | 200 | 130 | 33.4 | 89.9 | 1.9 |
| 165 | `GET /modules/vrp-activity-list` | 200 | 25 | 17.7 | 1.6 | 1.7 |
| 170 | `GET /users` | 200 | 50 | 29.4 | 18.2 | 2.0 |
| 174 | `GET /users/new` | 200 | 9316 | 804.0 | 215.0 | 2741.2 |
| 178 | `GET /users/new` | 200 | 230 | 116.7 | 63.9 | 55.5 |
| 182 | `GET /users/new` | 200 | 184 | 105.7 | 44.0 | 52.6 |
| 186 | `GET /modules/user-hierarchy-mapping` | 200 | 106 | 32.6 | 68.7 | 2.0 |
| 191 | `GET /modules/user-hierarchy-list` | 200 | 1340 | 1325.8 | 9.2 | 445.4 |
| 196 | `GET /modules/jeevika-jankar-transfer` | 200 | 127 | 64.4 | 60.5 | 7.7 |
| 201 | `GET /modules/jeevika-jankar-transfer-list` | 200 | 15 | 10.3 | 1.5 | 1.5 |
| 206 | `GET /modules/access-control` | 200 | 168 | 50.1 | 116.4 | 4.2 |
| 211 | `GET /modules/access-control-list` | 200 | 27 | 19.1 | 2.7 | 2.7 |
| 216 | `GET /modules/add-vrp-type` | 200 | 12 | 10.3 | 0.0 | 0.2 |
| 221 | `GET /vrps/new` | 200 | 9269 | 6570.2 | 2422.7 | 2068.2 |
| 226 | `GET /vrps/approvals` | 200 | 3781 | 31.1 | 42.4 | 872.2 |
| 230 | `GET /vrps/approvals` | 200 | 4016 | 39.3 | 79.1 | 1077.9 |
| 234 | `GET /modules/approval-master` | 200 | 87 | 17.5 | 67.3 | 0.6 |
| 239 | `GET /modules/approval-list` | 200 | 100 | 66.0 | 15.2 | 4.5 |
| 244 | `GET /vrp-agreements` | 200 | 627 | 113.6 | 433.3 | 6.4 |
| 248 | `GET /afls` | 200 | 39 | 26.2 | 8.1 | 0.4 |
| 252 | `GET /target_mappings` | 200 | 6311 | 1523.4 | 179.2 | 551.1 |
| 254 | `GET /target_mappings/list` | 200 | 1217 | 906.4 | 18.8 | 195.2 |
| 261 | `GET /jj-mapped-farmers` | 200 | 6804 | 12.9 | 104.6 | 4.2 |
| 265 | `GET /modules/training-form` | 200 | 2152 | 447.4 | 1702.8 | 73.2 |
| 271 | `GET /modules/training-form-list` | 200 | 1924 | 237.5 | 1525.1 | 60.0 |
| 277 | `GET /modules/training-form/records/183400/edit` | 200 | 1798 | 1571.9 | 220.4 | 335.2 |
| 282 | `GET /modules/training-form/training_target_farmers` | 200 | 223 | 0.3 | 68.2 | 21.1 |
| 286 | `GET /modules/training-form-list` | 200 | 2097 | 293.4 | 1629.5 | 102.5 |
| 292 | `GET /training_edit_approvals` | 200 | 1841 | 20.5 | 1814.8 | 0.0 |
| 294 | `GET /modules/training-form/records/183400/edit` | 200 | 2238 | 1877.5 | 356.1 | 430.7 |
| 302 | `GET /modules/training-form/training_target_farmers` | 200 | 178 | 0.5 | 54.7 | 26.6 |
| 306 | `GET /modules/other-target` | 200 | 511 | 344.2 | 99.6 | 226.8 |
| 311 | `GET /modules/other-target-list` | 200 | 422 | 286.8 | 39.2 | 114.1 |
| 316 | `GET /modules/other-target-with-farmer` | 200 | 510 | 356.9 | 105.6 | 59.7 |
| 321 | `GET /modules/other-target-with-farmer-list` | 200 | 155 | 108.3 | 12.1 | 18.9 |
| 326 | `GET /modules/jeevika-jankar-bill-process` | 200 | 304 | 10.4 | 257.5 | 0.0 |
| 331 | `GET /modules/jeevika-jankar-bill-list` | 200 | 8363 | 7532.0 | 624.7 | 1912.8 |
| 336 | `GET /modules/jeevika-jankar-bill-process/records/183403/edit` | 200 | 5802 | 12.8 | 636.4 | 1049.9 |
| 341 | `GET /modules/jeevika-jankar-bill-list` | 200 | 6584 | 5848.3 | 575.7 | 1016.5 |
| 346 | `GET /modules/jeevika-jankar-observation-list` | 200 | 29 | 11.0 | 10.9 | 0.0 |
| 351 | `GET /modules/jeevika-jankar-payment-list` | 200 | 2496 | 1092.0 | 295.9 | 292.3 |
| 356 | `GET /modules/jeevika-jankar-payment-list-detail` | 200 | 1482 | 209.6 | 97.9 | 397.8 |
| 361 | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 62 | 41.9 | 9.9 | 2.5 |
| 366 | `GET /jj-quizzes` | 200 | 84 | 16.9 | 38.4 | 0.6 |
| 370 | `GET /users/new` | 200 | 9234 | 440.0 | 243.9 | 2664.1 |
| 374 | `GET /vrps/new` | 200 | 820 | 464.2 | 84.0 | 396.6 |
| 378 | `GET /vrps` | 200 | 3293 | 12.9 | 65.7 | 470.7 |
| 382 | `GET /vrps/225/edit` | 200 | 5073 | 615.8 | 4079.1 | 184.4 |
| 389 | `GET /modules/approval-list` | 200 | 81 | 59.4 | 7.1 | 0.0 |
| 394 | `GET /target_mappings` | 200 | 159 | 41.3 | 26.1 | 0.0 |
| 398 | `GET /target_mappings/vrp_mappings` | 200 | 28 | 0.2 | 19.1 | 0.0 |
| 402 | `GET /modules/training-form-list` | 200 | 17646 | 18.3 | 123.1 | 3367.4 |
| 405 | `GET /modules/jeevika-jankar-bill-list` | 200 | 6065 | 579.8 | 320.2 | 1014.1 |
| 412 | `GET /modules/jeevika-jankar-payment-list` | 200 | 2491 | 1159.3 | 354.3 | 331.6 |
| 417 | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 2001 | 1949.4 | 43.6 | 447.6 |
| 422 | `GET /dashboard` | 200 | 2394 | 41.8 | 406.2 | 451.3 |
| 424 | `GET /jj-quizzes/question_template` | 200 | 7 | 0.5 | 0.0 | 0.0 |
| 428 | `GET /` | 302 | 2 | — | 0.0 | 0.0 |
| 432 | `GET /dashboard` | 200 | 1102 | 55.3 | 585.8 | 82.1 |
| 436 | `GET /dashboard` | 200 | 847 | 51.1 | 395.5 | 68.1 |

## Every slow SQL marker

| Request ID | SQL ms | Logged source |
|---|---:|---|
| `fed1cfcc` | 1715.5 | `app/controllers/modules_controller.rb:16523` |
| `935e91c4` | 1412.1 | `app/controllers/modules_controller.rb:16499` |
| `056e4746` | 1121.9 | `app/controllers/modules_controller.rb:16499` |
| `759572fe` | 2955.3 | `app/controllers/modules_controller.rb:16971` |
| `9c8d61e5` | 1430.4 | `app/controllers/vrps_controller.rb:2105` |
| `70616040` | 1500.9 | `app/controllers/modules_controller.rb:16971` |
| `c278abdd` | 1426.9 | `app/controllers/modules_controller.rb:9467` |
| `0b10d7ca` | 1502.9 | `app/controllers/modules_controller.rb:9467` |
| `44c4c6b7` | 1799.7 | `app/services/training_edit_approval.rb:212` |
| `eebf730e` | 815.5 | `app/controllers/vrps_controller.rb:2242` |
| `eebf730e` | 1400.5 | `app/controllers/vrps_controller.rb:2242` |

## Remaining work

No production deployment or post-patch production speed measurement was performed. The 17.646-second production training-list request is not claimed to be a 4-ms HTTP request. This patch removes a confirmed all-candidate load for admins and provides stage evidence to locate the large remaining gap. Staff paths, cold location builds, bill calculations/rendering and external API waits are not all solved. Existing ten failing/error checks remain documented; no unrelated business rule was changed just to make tests pass.

After deploying this backend patch and restarting the app, the next log should contain phase entries for any remaining slow reads; those entries will distinguish catalogue building, visibility, financial preparation and external calls instead of relying on SQL/GC totals alone.
