# Request-by-request log audit — 9 November 2026

Latest expanded code audit: **200 tests / 2,221 assertions; 190 tests pass, six failures and four errors remain**. All ten failing/error test names match the original-controller baseline. Two additional photo expectation/validation failures were found beyond the eight previously documented checks. These include test setup/expectation problems as well as potential application issues; they are not ten confirmed production defects. See the fourth audit in `PERFORMANCE_ACTION_RESCAN_20261109.md` for the breakdown.

All 91 request IDs and all 16 `PERFORMANCE_SQL` entries in the supplied 441-line attachment were inspected. This attachment is byte-identical to the earlier supplied log; it is not evidence of post-fix production speed. There are 86 HTTP 200 and five HTTP 302 completions, no recorded HTTP 4xx/5xx, 36 requests over one second and 16 over five seconds. The capture contains 89 GETs, one login POST and one partial request whose start is absent. There are no captured update/delete submissions, so their production latency or success cannot be inferred.

Timings below are from the supplied production log, not new measurements. GC overlaps other timing categories and must not be added to SQL/view durations. Logged source line numbers refer to the production code at capture time. Findings distinguish changed code from unresolved investigation; a slow request does not by itself identify its root cause. Query strings are omitted from the table.

## Every request, in capture order

| Log line | Request ID | Method/path | Status | Total ms | View ms | DB ms | GC ms | Review |
|---:|---|---|---:|---:|---:|---:|---:|---|
| 3 | `67ba534e` | `Partial request` | 302 | 512 | — | 50.6 | 42.6 | Capture starts mid-request; originating action and HTTP method unavailable. |
| 5 | `9c36f568` | `GET /target_mappings` | 200 | 517 | 308.9 | 54.0 | 99.2 | Target read retained; no further bottleneck established from this request. |
| 9 | `e0020fa0` | `GET /target_mappings/vrp_mappings` | 200 | 35 | 0.2 | 21.5 | 2.2 | Target read retained; no further bottleneck established from this request. |
| 13 | `fdd3fb13` | `GET /` | 302 | 7 | — | 1.3 | 0.9 | Response retained; no additional bottleneck established from this request. |
| 17 | `20016e9f` | `GET /dashboard` | 200 | 9273 | 58.3 | 319.7 | 2326.8 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |
| 19 | `0769ad27` | `GET /` | 302 | 5 | — | 1.4 | 0.0 | Response retained; no additional bottleneck established from this request. |
| 23 | `d9b1c619` | `GET /dashboard` | 200 | 1128 | 62.3 | 516.6 | 66.5 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |
| 29 | `907031bc` | `GET /modules/lg-directory-list` | 200 | 12610 | 899.7 | 1736.6 | 2990.7 | Existing projection/cache/pagination retained; cold read/render cost not established locally. |
| 35 | `f3476b4d` | `GET /modules/state-master` | 200 | 58 | 14.5 | 36.7 | 0.2 | Existing projection/cache/pagination retained; cold read/render cost not established locally. |
| 40 | `f0e4a437` | `GET /modules/training-form-list` | 200 | 454 | 37.0 | 111.1 | 34.0 | Repeated candidate SQL construction fixed; latest-revision query can still have DB cost. |
| 43 | `f9f99168` | `GET /modules/district-master` | 200 | 189 | 127.6 | 44.0 | 61.2 | Existing projection/cache/pagination retained; cold read/render cost not established locally. |
| 50 | `7a3f32ed` | `GET /modules/block-master` | 200 | 366 | 278.8 | 48.0 | 195.3 | Existing projection/cache/pagination retained; cold read/render cost not established locally. |
| 55 | `c5ca46c0` | `GET /modules/gram-panchayat-master` | 200 | 9966 | 7018.4 | 1843.6 | 2277.6 | Existing projection/cache/pagination retained; cold read/render cost not established locally. |
| 59 | `ad51191a` | `GET /modules/village-master` | 200 | 4411 | 747.0 | 107.7 | 1288.3 | Existing projection/cache/pagination retained; cold read/render cost not established locally. |
| 66 | `50f04636` | `GET /modules/month-master` | 200 | 841 | 21.4 | 815.4 | 2.2 | Response retained; no additional bottleneck established from this request. |
| 71 | `4de940ec` | `GET /modules/stakeholder-master` | 200 | 15 | 10.8 | 1.3 | 0.5 | Response retained; no additional bottleneck established from this request. |
| 76 | `7c64a15f` | `GET /modules/stakeholder-role` | 200 | 35 | 24.6 | 6.3 | 2.7 | Response retained; no additional bottleneck established from this request. |
| 81 | `0cd99dc3` | `GET /modules/role-name` | 200 | 54 | 35.1 | 13.0 | 5.0 | Response retained; no additional bottleneck established from this request. |
| 86 | `21e36a85` | `GET /modules/parent-office-add` | 200 | 53 | 27.3 | 22.0 | 2.0 | Response retained; no additional bottleneck established from this request. |
| 91 | `97d68ff1` | `GET /modules/office-category-add` | 200 | 45 | 25.6 | 13.5 | 2.4 | Response retained; no additional bottleneck established from this request. |
| 96 | `2ae0ea01` | `GET /modules/office-mapping-add` | 200 | 66 | 44.1 | 14.9 | 3.9 | Response retained; no additional bottleneck established from this request. |
| 101 | `e065308a` | `GET /modules/office-list` | 200 | 4137 | 29.4 | 1.6 | 105.1 | High non-SQL or view time; no specific additional code bottleneck established. |
| 106 | `7fd1c47e` | `GET /asa360-mapping` | 200 | 30 | 11.7 | 6.2 | 1.5 | Response retained; no additional bottleneck established from this request. |
| 110 | `4a78ed8c` | `GET /modules/project-master` | 200 | 67 | 50.4 | 1.6 | 33.7 | Response retained; no additional bottleneck established from this request. |
| 115 | `6f56c3ae` | `GET /modules/add-activity-group` | 200 | 2537 | 31.1 | 2501.1 | 3.1 | Slow scalar dropdown query recorded; database plan/wait not available in this log. |
| 121 | `8c482b9d` | `GET /modules/activity-group-list` | 200 | 43 | 27.1 | 1.7 | 23.3 | Response retained; no additional bottleneck established from this request. |
| 126 | `66a499ee` | `GET /modules/add-vrp-activity` | 200 | 55 | 40.6 | 5.1 | 9.1 | Response retained; no additional bottleneck established from this request. |
| 131 | `bea6c047` | `GET /modules/vrp-activity-list` | 200 | 27 | 19.6 | 1.7 | 2.3 | Response retained; no additional bottleneck established from this request. |
| 136 | `7888d4db` | `GET /users` | 200 | 42 | 34.6 | 4.4 | 8.0 | Response retained; no additional bottleneck established from this request. |
| 140 | `34c4e63a` | `GET /users/112/edit` | 200 | 10401 | 464.4 | 216.9 | 2105.6 | Existing form cache retained; high non-SQL/GC time requires runtime profile. |
| 145 | `079a5da0` | `GET /users/new` | 200 | 11281 | 322.5 | 244.1 | 2759.9 | Existing form cache retained; high non-SQL/GC time requires runtime profile. |
| 149 | `324dc60f` | `GET /modules/user-hierarchy-mapping` | 200 | 39 | 27.2 | 6.5 | 5.0 | Response retained; no additional bottleneck established from this request. |
| 154 | `ccc11232` | `GET /modules/user-hierarchy-list` | 200 | 1617 | 1572.1 | 39.5 | 499.2 | High non-SQL or view time; no specific additional code bottleneck established. |
| 159 | `6ee951e9` | `GET /modules/jeevika-jankar-transfer` | 200 | 78 | 64.6 | 11.3 | 10.5 | Response retained; no additional bottleneck established from this request. |
| 164 | `6458d477` | `GET /modules/jeevika-jankar-transfer-list` | 200 | 19 | 12.7 | 3.3 | 1.6 | Response retained; no additional bottleneck established from this request. |
| 169 | `e8ed7f05` | `GET /modules/access-control` | 200 | 65 | 56.1 | 7.4 | 7.7 | Response retained; no additional bottleneck established from this request. |
| 174 | `21e4e263` | `GET /modules/access-control-list` | 200 | 18 | 13.1 | 1.4 | 1.5 | Response retained; no additional bottleneck established from this request. |
| 179 | `18f9af23` | `GET /modules/add-vrp-type` | 200 | 12 | 10.2 | 0.0 | 0.9 | Response retained; no additional bottleneck established from this request. |
| 184 | `26f2de3e` | `GET /vrps/new` | 200 | 10329 | 7829.5 | 2201.1 | 2520.6 | Selected admin detail already direct; staff visibility scan remains to profile. |
| 187 | `9d95376f` | `GET /vrps` | 200 | 250 | 28.7 | 28.3 | 19.9 | Response retained; no additional bottleneck established from this request. |
| 191 | `fa0d809e` | `GET /vrps/7` | 200 | 299 | 171.2 | 73.1 | 70.9 | Selected admin detail already direct; staff visibility scan remains to profile. |
| 198 | `a9198192` | `GET /vrps/7/edit` | 200 | 14034 | 6638.6 | 6690.9 | 1713.1 | Staff selected-row lookup optimized; location queries/cache costs also present. |
| 202 | `83215d00` | `GET /modules/training-form-list` | 200 | 851 | 37.5 | 256.4 | 294.4 | Repeated candidate SQL construction fixed; latest-revision query can still have DB cost. |
| 213 | `eb697790` | `GET /vrps/approvals` | 200 | 3903 | 31.9 | 22.4 | 1079.6 | High non-SQL or view time; no specific additional code bottleneck established. |
| 217 | `b90c2bec` | `GET /modules/approval-master` | 200 | 31 | 23.5 | 5.0 | 8.8 | Response retained; no additional bottleneck established from this request. |
| 222 | `00065a9b` | `GET /modules/approval-list` | 200 | 100 | 77.8 | 4.6 | 5.7 | Response retained; no additional bottleneck established from this request. |
| 227 | `6ee988fe` | `GET /vrp-agreements` | 200 | 582 | 137.7 | 373.8 | 0.0 | Response retained; no additional bottleneck established from this request. |
| 231 | `f8d45cee` | `GET /afls` | 200 | 44 | 30.3 | 9.0 | 1.5 | Response retained; no additional bottleneck established from this request. |
| 235 | `552efe43` | `GET /target_mappings` | 200 | 5924 | 1846.8 | 56.4 | 464.0 | Existing target read paths retained; slow Ruby/rendering needs runtime profile. |
| 239 | `d72d95ee` | `GET /target_mappings/vrp_mappings` | 200 | 41 | 0.2 | 24.5 | 0.6 | Target read retained; no further bottleneck established from this request. |
| 243 | `9a12ff8e` | `GET /target_mappings/list` | 200 | 1286 | 954.1 | 16.4 | 306.7 | Existing target read paths retained; slow Ruby/rendering needs runtime profile. |
| 248 | `7a44e965` | `GET /jj-mapped-farmers` | 200 | 7330 | 14.2 | 89.2 | 3.1 | Existing target read paths retained; slow Ruby/rendering needs runtime profile. |
| 250 | `11d04e65` | `GET /modules/training-form` | 200 | 1340 | 49.6 | 1279.8 | 0.0 | Slow scalar dropdown query recorded; database plan/wait not available in this log. |
| 258 | `0a0079ad` | `GET /modules/training-form` | 200 | 1775 | 525.3 | 1247.8 | 84.3 | Slow scalar dropdown query recorded; database plan/wait not available in this log. |
| 264 | `b963530b` | `GET /modules/training-form-list` | 200 | 11152 | 1244.1 | 1336.6 | 1661.2 | Repeated candidate SQL construction fixed; latest-revision query can still have DB cost. |
| 267 | `4ad1b586` | `GET /modules/training-form/training_target_farmers` | 200 | 336 | 0.5 | 82.4 | 6.7 | Response retained; no additional bottleneck established from this request. |
| 274 | `a06556de` | `GET /login` | 200 | 6 | 4.9 | 0.0 | 0.2 | Response retained; no additional bottleneck established from this request. |
| 278 | `8ee93020` | `GET /modules/training-form/records/183400/edit` | 200 | 5538 | 1775.1 | 3741.7 | 444.4 | Edit now reads only selected training revision; form dropdown costs remain. |
| 282 | `70df4c78` | `POST /login` | 302 | 16 | — | 6.0 | 0.0 | Response retained; no additional bottleneck established from this request. |
| 287 | `e9d65908` | `GET /dashboard` | 200 | 1613 | 19.1 | 829.0 | 106.9 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |
| 294 | `d625c09a` | `GET /modules/training-form/training_target_farmers` | 200 | 290 | 0.5 | 75.4 | 6.3 | Response retained; no additional bottleneck established from this request. |
| 298 | `a3c4d676` | `GET /modules/training-form` | 200 | 1228 | 51.1 | 1166.5 | 7.0 | Slow scalar dropdown query recorded; database plan/wait not available in this log. |
| 301 | `795d8200` | `GET /dashboard/vrp-list/achieved_target` | 200 | 758 | 11.3 | 158.8 | 70.8 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |
| 309 | `5e719da7` | `GET /modules/other-target` | 200 | 526 | 369.4 | 70.1 | 265.6 | Response retained; no additional bottleneck established from this request. |
| 314 | `81c857dd` | `GET /modules/other-target-list` | 200 | 429 | 312.8 | 44.3 | 69.9 | Response retained; no additional bottleneck established from this request. |
| 319 | `d386760d` | `GET /modules/other-target-with-farmer` | 200 | 461 | 327.4 | 90.5 | 68.7 | Response retained; no additional bottleneck established from this request. |
| 324 | `0cefd1f9` | `GET /modules/other-target-with-farmer-list` | 200 | 140 | 96.2 | 10.4 | 0.0 | Response retained; no additional bottleneck established from this request. |
| 329 | `23f088b0` | `GET /modules/jeevika-jankar-bill-process` | 200 | 372 | 11.2 | 323.4 | 0.0 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 334 | `3de972c8` | `GET /modules/jeevika-jankar-bill-list` | 200 | 7713 | 6972.7 | 549.2 | 1558.8 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 339 | `eead0e8a` | `GET /modules/jeevika-jankar-bill-process/records/183403/edit` | 200 | 5049 | 12.2 | 716.9 | 674.9 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 344 | `ce88872d` | `GET /modules/jeevika-jankar-observation-list` | 200 | 24 | 8.8 | 7.2 | 0.0 | Response retained; no additional bottleneck established from this request. |
| 349 | `c39aa487` | `GET /modules/jeevika-jankar-payment-list` | 200 | 2639 | 1049.3 | 306.2 | 487.7 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 354 | `159b940e` | `GET /modules/jeevika-jankar-payment-list-detail` | 200 | 1646 | 234.6 | 132.7 | 421.3 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 359 | `7c049cc8` | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 53 | 38.9 | 7.9 | 0.0 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 364 | `74e959f3` | `GET /jj-quizzes` | 200 | 74 | 16.4 | 28.2 | 0.0 | Response retained; no additional bottleneck established from this request. |
| 368 | `3a98a317` | `GET /modules/training-form` | 200 | 1959 | 48.7 | 1898.9 | 0.0 | Slow scalar dropdown query recorded; database plan/wait not available in this log. |
| 371 | `fa245120` | `GET /dashboard` | 200 | 8356 | 33.8 | 354.9 | 1449.8 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |
| 376 | `23e048d1` | `GET /users/new` | 200 | 611 | 415.1 | 80.2 | 184.0 | Existing form cache retained; high non-SQL/GC time requires runtime profile. |
| 382 | `e33f6419` | `GET /vrps/new` | 200 | 582 | 152.0 | 121.3 | 124.5 | Selected admin detail already direct; staff visibility scan remains to profile. |
| 386 | `1bc4b6f6` | `GET /vrps` | 200 | 4166 | 12.4 | 61.7 | 834.1 | High non-SQL or view time; no specific additional code bottleneck established. |
| 390 | `f0280eb2` | `GET /modules/approval-list` | 200 | 187 | 134.4 | 7.5 | 86.1 | Response retained; no additional bottleneck established from this request. |
| 395 | `c9c56ac9` | `GET /vrps` | 200 | 3135 | 9.9 | 47.6 | 510.2 | High non-SQL or view time; no specific additional code bottleneck established. |
| 399 | `5f4f75ed` | `GET /target_mappings` | 200 | 145 | 38.5 | 31.0 | 0.0 | Target read retained; no further bottleneck established from this request. |
| 403 | `b64db740` | `GET /target_mappings/vrp_mappings` | 200 | 30 | 0.2 | 16.7 | 2.9 | Target read retained; no further bottleneck established from this request. |
| 407 | `9dc830b9` | `GET /modules/training-form-list` | 200 | 20365 | 15.4 | 103.8 | 4397.6 | Repeated candidate SQL construction fixed; latest-revision query can still have DB cost. |
| 410 | `5bb51f64` | `GET /modules/jeevika-jankar-bill-list` | 200 | 7104 | 569.5 | 490.1 | 1654.9 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 415 | `61aa5304` | `GET /modules/jeevika-jankar-payment-list` | 200 | 2852 | 1338.0 | 270.3 | 735.1 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 420 | `c2059f4e` | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 2508 | 2450.2 | 47.1 | 646.9 | Billing calculation/render cost remains; billing mutation/summary regressions passed. |
| 427 | `0b69881b` | `GET /` | 302 | 4 | — | 0.0 | 1.6 | Response retained; no additional bottleneck established from this request. |
| 431 | `6b16fc8b` | `GET /dashboard` | 200 | 1348 | 63.9 | 563.1 | 141.1 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |
| 435 | `9e323991` | `GET /dashboard` | 200 | 1411 | 54.8 | 574.1 | 286.7 | Existing aggregate caches retained; legacy FCO label behavior restored; profile remaining calculations/GC. |

## Every slow SQL marker

| Request ID | SQL ms | Logged source |
|---|---:|---|
| `907031bc` | 1606.6 | `app/controllers/modules_controller.rb:16476` |
| `c5ca46c0` | 1783.0 | `app/controllers/modules_controller.rb:16452` |
| `6f56c3ae` | 2496.4 | `app/controllers/modules_controller.rb:16915` |
| `26f2de3e` | 1315.2 | `app/controllers/vrps_controller.rb:2097` |
| `a9198192` | 823.8 | `app/controllers/vrps_controller.rb:2234` |
| `a9198192` | 937.7 | `app/controllers/vrps_controller.rb:2234` |
| `a9198192` | 959.5 | `app/controllers/vrps_controller.rb:2234` |
| `a9198192` | 1229.3 | `app/controllers/vrps_controller.rb:2234` |
| `a9198192` | 1401.5 | `app/controllers/vrps_controller.rb:2097` |
| `11d04e65` | 1227.1 | `app/controllers/modules_controller.rb:16915` |
| `0a0079ad` | 1192.0 | `app/controllers/modules_controller.rb:16915` |
| `b963530b` | 1198.3 | `app/controllers/modules_controller.rb:9460` |
| `8ee93020` | 2327.0 | `app/controllers/modules_controller.rb:9460` |
| `8ee93020` | 1273.0 | `app/controllers/modules_controller.rb:16915` |
| `a3c4d676` | 1141.2 | `app/controllers/modules_controller.rb:16915` |
| `3a98a317` | 1865.6 | `app/controllers/modules_controller.rb:16915` |

## Behavior review and verification

- A real authenticated training-edit regression now passes with both current and original controller methods. Live training data and before/proposed snapshots remain intact, automatic Agronomist routing remains active, opening the page creates no additional revision, and reopening is stable. The existing sidebar may route other visible pending requests during rendering; the targeted edit-helper optimization preserves that behavior and does not eliminate all page-wide revision work. Earlier rendering-stubbed benchmarks exclude this sidebar work.
- Latest follow-up: single-JJ staff actions also restrict the cluster-label query itself to the requested ID. Full-list fuzzy matching and own-or-mapped authorization parity passed across 60 selected-record cases. Final focused run: **140 tests / 1,972 assertions, zero failures/errors**. Rollback-only synthetic actual-Rails staff lookup benchmark: **17.04 ms / 501 label comparisons to 2.84 ms / one comparison**, with complete returned attributes identical. These are lookup timings, not HTTP/production timings; previously documented baseline issues remain unresolved.
- Corrected a behavior edge introduced by the earlier dashboard `DISTINCT` change: without a matching FCO-directory entry, alias groups use the first original saved label. PostgreSQL DISTINCT can reorder those labels. A rollback-only comparison reproduced `Parity Unknown` becoming `FCO-C Parity Unknown`; DISTINCT was removed. A dashboard integration test pins the original label.
- Retained the request-local training revision query-build fix. Latest revision still wins by ID; missing results remain cached; pending ordering and automatic routing remain unchanged.
- Training edit now supplies only its selected training ID to the existing indexed latest-revision reader. Tests compare complete summary data for Approved, Rejected and Pending revisions, preserve ID-over-timestamp precedence, reject leading-zero legacy references, and verify only selected training plus latest revision are instantiated.
- Staff JJ edit/update/delete still require own-or-cluster-mapped authorization and return complete selected-record attributes. No visibility rule or mutation response was changed by this rescan.
- Final focused verification: 136 tests, 1,888 assertions, zero failures/errors. This includes dashboard alias integration, revision reads, monthly training, approval transitions, staff scope, JJ actions, bill mutation redirects, billing summaries, user forms and location ordering.
- Additional broad checks found eight distinct pre-existing failures/errors across attendance, similar-name visibility, controller-less request setup, saved contact fallback, FCO SQL query-count expectations and incomplete VRP test fixtures. All eight reproduce after replacing every modified controller method with its original Git version in memory. They are unresolved and are not reported as passing.
- Previous actual-Rails training-list helper benchmark: 4,640.40 ms to 5.05 ms for 1,000 candidate IDs across three passes. New synthetic edit-action benchmark: 10.50 ms / 502 instantiated rows to 1.68 ms / two rows with 500 unrelated revisions; revision output identical. Edit benchmark stubs authorization/rendering and rolls back fixtures. Neither benchmark measures full HTTP latency.
- No deployment or authenticated production measurement was performed. Cold dropdown SQL, global dashboard/bill calculations, staff detail visibility scans and host CPU/memory/database waits remain candidates for further production profiling. There is no verified 3–5 ms application-wide latency guarantee.
