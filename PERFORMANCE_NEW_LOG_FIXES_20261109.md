# New production log audit and performance fixes — 9 November 2026

Baseline: Git `e0605f4`. This audit covers every line of the new supplied log: 424 lines, 86 complete requests, 14 slow-SQL markers, 78 HTTP 200 and eight HTTP 302 responses. Thirty-eight requests exceed one second. Startup lines show Puma/Solid Queue startup; they are not request timings. No recorded 4xx/5xx or edit/delete submissions appear in this capture. These production timings precede this patch; no deployment or new production timing was performed.

## Implemented fixes

- Legacy owner visibility: replace repeated all-JJ scans for name/contact-only records with a request-local normalized-label index. Preserve all nine record aliases, all five owner labels, blank handling and earliest source-position matching. Explicit owner-ID precedence and final permission predicates remain in place.
- Master lists: cache the original Ruby-sorted attribute rows by catalogue revision and fields. On warm unfiltered HTML pages, instantiate only the existing 15-row page. Existing search, export/edit handling, page counts, out-of-range clamping, inactive records, complete record attributes and equal-sort-key order are retained.
- Generic/module dropdowns: cache the original scalar projection with the exact SQL scope, field-key order, database and live tuple revision in the key. The metadata probe uses ID/xmin/ctid without decoding photo JSON. Direct repeated edits, deletion and savepoint rollback invalidate correctly. Cold fills use the existing concurrency-safe CatalogueReadCache check; returned values are deeply copied.
- Modules/JJ/user field helpers: stop at the first present value or first non-code location label. Keep false/blank handling, value types, key priority and first numeric-code fallback. This removes unused array allocations and repeated serialized-data reads.

## Validation and benchmarks

- Combined run: **212 tests / 3,434 assertions; 202 tests pass, six failures and four errors remain**. All ten failing/error test names match the pre-task baseline after every modified controller method was restored from `e0605f4` in memory. No new failure was found in the examined suite.
- New parity cases cover JSON types/blank handling across all three controllers, ambiguous legacy owners and source ordering, warm master page attributes/counts, search/action-label matching, cache mutation isolation, direct writes, hard deletes and savepoint rollback. Existing billing, approvals, real authenticated training edits, sidebar behavior, master UI actions and staff scope tests were included.
- Actual-Rails synthetic visibility benchmark: 500 legacy records and 500 owners; **1,050.30 ms / 5,018,573 allocations → 5.97 ms / 31,507 allocations**. Returned owner IDs match.
- Warm 1,000-row master catalogue: **20.86 ms / 60,741 allocations → 13.05 ms / 27,845 allocations**. Complete selected-page attributes match; regression verifies no more than 15 visible records instantiated on a warm hit.
- Scalar dropdown over 200 photo-heavy rows: **6.55 ms original; 7.16 ms new cold; 1.46 ms new warm**. Full values and order match. The cold overhead is explicitly included; caching does not accelerate the first query.
- Benchmark fixtures roll back. These are helper/read measurements, not full authenticated HTTP or production latency. Syntax and diff checks pass.

## Every request in capture order

View/SQL/GC times overlap; do not add GC to other categories. Source line references below refer to the deployed code in the supplied log. Query strings and client addresses are omitted.

| Line | Request ID | Request | Status | Total ms | View ms | SQL ms | GC ms | Review |
|---:|---|---|---:|---:|---:|---:|---:|---|
| 12 | `97d8bd59` | `GET /` | 302 | 261 | — | 60.1 | 15.7 | Reviewed; no additional code-specific bottleneck established from this request. |
| 16 | `b49eb023` | `GET /dashboard` | 200 | 10072 | 142.5 | 552.6 | 2152.2 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 20 | `74e4992c` | `GET /` | 302 | 2 | — | 0.0 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 24 | `f5514ada` | `GET /dashboard` | 200 | 9338 | 43.6 | 209.5 | 2032.4 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 28 | `3788b591` | `GET /modules/lg-directory-list` | 200 | 12334 | 861.4 | 1870.9 | 2830.5 | Shared field readers exit early; existing projection/directory caches retained. Cold directory SQL/build cost remains. |
| 31 | `80154885` | `GET /modules/state-master` | 200 | 215 | 137.1 | 67.1 | 8.2 | Warm unfiltered pages instantiate only 15 rows; original sort/search retained; scalar dropdowns cached by live tuple revision. Cold location reads remain. |
| 36 | `08bd6dd1` | `GET /modules/district-master` | 200 | 9447 | 7679.0 | 1748.8 | 2336.5 | Warm unfiltered pages instantiate only 15 rows; original sort/search retained; scalar dropdowns cached by live tuple revision. Cold location reads remain. |
| 39 | `1dc80a75` | `GET /modules/block-master` | 200 | 16364 | 7279.9 | 8904.5 | 3830.4 | Warm unfiltered pages instantiate only 15 rows; original sort/search retained; scalar dropdowns cached by live tuple revision. Cold location reads remain. |
| 46 | `e7b0c2f1` | `GET /modules/gram-panchayat-master` | 200 | 8781 | 162.3 | 6306.5 | 2208.8 | Warm unfiltered pages instantiate only 15 rows; original sort/search retained; scalar dropdowns cached by live tuple revision. Cold location reads remain. |
| 53 | `4e6742c4` | `GET /modules/stakeholder-master` | 200 | 23 | 10.2 | 8.9 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 58 | `61efb4a9` | `GET /modules/stakeholder-role` | 200 | 31 | 20.0 | 7.0 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 63 | `03da7655` | `GET /modules/role-name` | 200 | 50 | 29.5 | 15.9 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 68 | `94dd75a1` | `GET /modules/parent-office-add` | 200 | 45 | 23.6 | 16.5 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 73 | `e1bc43c9` | `GET /modules/office-category-add` | 200 | 40 | 22.4 | 12.6 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 78 | `8043ac7b` | `GET /modules/office-mapping-add` | 200 | 69 | 34.2 | 28.5 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 89 | `99066af3` | `GET /modules/village-master` | 200 | 4488 | 567.8 | 151.0 | 1300.7 | Warm unfiltered pages instantiate only 15 rows; original sort/search retained; scalar dropdowns cached by live tuple revision. Cold location reads remain. |
| 92 | `b725dd1e` | `GET /modules/month-master` | 200 | 2372 | 220.7 | 2145.3 | 529.1 | Scalar dropdown projection now cached by source revision; first cold read still executes original SQL. |
| 95 | `a99d9439` | `GET /modules/office-list` | 200 | 3588 | 24.3 | 2.3 | 11.4 | Code awaits live external Office API/fallback. Remote latency not measured separately; freshness behavior retained. |
| 101 | `3c92d021` | `GET /asa360-mapping` | 200 | 29 | 9.6 | 8.1 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 109 | `9bdfdab0` | `GET /modules/project-master` | 200 | 41 | 30.0 | 2.3 | 2.6 | Reviewed; no additional code-specific bottleneck established from this request. |
| 114 | `da79b4f8` | `GET /modules/add-activity-group` | 200 | 3405 | 37.3 | 3361.9 | 3.2 | Scalar dropdown projection now cached by source revision; first cold read still executes original SQL. |
| 117 | `47cc9cba` | `GET /modules/activity-group-list` | 200 | 23 | 16.3 | 2.0 | 4.4 | Reviewed; no additional code-specific bottleneck established from this request. |
| 125 | `7d6d0b6f` | `GET /modules/add-vrp-activity` | 200 | 43 | 29.8 | 7.1 | 1.9 | Reviewed; no additional code-specific bottleneck established from this request. |
| 130 | `3e86e9bc` | `GET /modules/vrp-activity-list` | 200 | 31 | 21.2 | 1.9 | 6.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 135 | `7c4fcfcd` | `GET /users` | 200 | 62 | 33.1 | 25.9 | 3.4 | Reviewed; no additional code-specific bottleneck established from this request. |
| 139 | `7aa2385d` | `GET /users/new` | 200 | 11012 | 811.0 | 291.3 | 2614.9 | Shared field readers avoid unused aliases; original values/fallbacks retained. Cold form/location cache build remains. |
| 143 | `63d0c75c` | `GET /users` | 200 | 40 | 32.2 | 5.3 | 5.2 | Reviewed; no additional code-specific bottleneck established from this request. |
| 147 | `d4077b05` | `GET /users/112/edit` | 200 | 406 | 308.4 | 54.4 | 46.5 | Shared field readers avoid unused aliases; original values/fallbacks retained. Cold form/location cache build remains. |
| 152 | `b1f8f25a` | `GET /modules/user-hierarchy-mapping` | 200 | 39 | 24.6 | 9.8 | 1.9 | Reviewed; no additional code-specific bottleneck established from this request. |
| 157 | `8124c346` | `GET /modules/user-hierarchy-list` | 200 | 1562 | 1519.7 | 36.4 | 508.4 | Reviewed; no additional code-specific bottleneck established from this request. |
| 162 | `0dd75799` | `GET /modules/jeevika-jankar-transfer` | 200 | 76 | 61.4 | 13.0 | 13.8 | Reviewed; no additional code-specific bottleneck established from this request. |
| 167 | `f5fd6f29` | `GET /modules/jeevika-jankar-transfer-list` | 200 | 17 | 11.9 | 1.8 | 2.7 | Reviewed; no additional code-specific bottleneck established from this request. |
| 172 | `1d5f3b41` | `GET /modules/access-control` | 200 | 62 | 48.1 | 9.6 | 7.5 | Reviewed; no additional code-specific bottleneck established from this request. |
| 177 | `42b87eb5` | `GET /modules/access-control-list` | 200 | 40 | 20.2 | 13.4 | 3.7 | Reviewed; no additional code-specific bottleneck established from this request. |
| 182 | `19745c0c` | `GET /modules/add-vrp-type` | 200 | 12 | 10.6 | 0.0 | 1.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 187 | `7a19372d` | `GET /vrps/new` | 200 | 10980 | 8171.2 | 2477.1 | 3322.4 | Shared field readers avoid unused aliases; original values/fallbacks retained. Cold form/location cache build remains. |
| 192 | `f2b56eff` | `GET /vrps/approvals` | 200 | 3429 | 38.0 | 50.4 | 966.4 | Reviewed; no additional code-specific bottleneck established from this request. |
| 196 | `eee2bafe` | `GET /modules/approval-master` | 200 | 45 | 16.0 | 27.0 | 0.9 | Reviewed; no additional code-specific bottleneck established from this request. |
| 201 | `7cacb3da` | `GET /modules/approval-list` | 200 | 96 | 74.1 | 5.5 | 6.8 | Reviewed; no additional code-specific bottleneck established from this request. |
| 206 | `6b9096b2` | `GET /vrp-agreements` | 200 | 606 | 109.6 | 421.1 | 16.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 210 | `f5966c4c` | `GET /afls` | 200 | 78 | 64.4 | 9.8 | 12.8 | Reviewed; no additional code-specific bottleneck established from this request. |
| 214 | `ffdbab62` | `GET /target_mappings` | 200 | 5369 | 1332.9 | 84.6 | 376.5 | Reviewed; no additional code-specific bottleneck established from this request. |
| 218 | `af16b163` | `GET /target_mappings/vrp_mappings` | 200 | 103 | 0.3 | 33.3 | 5.9 | Reviewed; no additional code-specific bottleneck established from this request. |
| 222 | `ad0cdde1` | `GET /target_mappings/list` | 200 | 1311 | 880.9 | 55.7 | 156.1 | Reviewed; no additional code-specific bottleneck established from this request. |
| 227 | `c993bed8` | `GET /jj-mapped-farmers` | 200 | 8004 | 13.6 | 77.3 | 7.5 | Code loads external JJ catalogue. Remote latency not measured separately; existing freshness retained. |
| 231 | `bfd77738` | `GET /modules/training-form` | 200 | 2373 | 422.1 | 1949.2 | 34.9 | Scalar dropdown projection now cached by source revision; first cold read still executes original SQL. |
| 237 | `76a4db3b` | `GET /modules/training-form-list` | 200 | 2155 | 450.3 | 1507.7 | 245.8 | Indexed legacy owner fallback; original pending/latest rules retained. Production residual timing unverified. |
| 243 | `f5522e10` | `GET /modules/other-target` | 200 | 351 | 168.9 | 118.1 | 62.4 | Reviewed; no additional code-specific bottleneck established from this request. |
| 248 | `4f08e71a` | `GET /modules/other-target-list` | 200 | 500 | 427.9 | 13.2 | 202.2 | Reviewed; no additional code-specific bottleneck established from this request. |
| 253 | `0740bea1` | `GET /modules/other-target-with-farmer` | 200 | 668 | 473.2 | 124.3 | 173.9 | Reviewed; no additional code-specific bottleneck established from this request. |
| 258 | `d2337704` | `GET /modules/other-target-with-farmer-list` | 200 | 213 | 153.2 | 10.6 | 49.2 | Reviewed; no additional code-specific bottleneck established from this request. |
| 263 | `b600fb36` | `GET /modules/training-form-list` | 200 | 1805 | 287.9 | 1334.8 | 99.0 | Indexed legacy owner fallback; original pending/latest rules retained. Production residual timing unverified. |
| 269 | `1618efb2` | `GET /modules/training-form/records/183400/edit` | 200 | 3288 | 1745.6 | 1536.3 | 425.2 | Scalar dropdown projection now cached by source revision; first cold read still executes original SQL. |
| 275 | `ef8c13eb` | `GET /modules/training-form/training_target_farmers` | 200 | 310 | 0.5 | 101.1 | 53.4 | Reviewed; no additional code-specific bottleneck established from this request. |
| 279 | `686df317` | `GET /modules/jeevika-jankar-bill-process` | 200 | 373 | 12.1 | 318.8 | 2.5 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 284 | `78ddb4f2` | `GET /modules/jeevika-jankar-bill-list` | 200 | 7928 | 6812.3 | 847.2 | 1382.4 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 289 | `9dfe2ba5` | `GET /modules/jeevika-jankar-bill-process/records/183403/edit` | 200 | 6049 | 16.9 | 729.5 | 992.0 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 294 | `2f5dcae7` | `GET /modules/jeevika-jankar-observation-list` | 200 | 20 | 7.9 | 5.9 | 0.3 | Reviewed; no additional code-specific bottleneck established from this request. |
| 299 | `1af772ec` | `GET /modules/jeevika-jankar-payment-list` | 200 | 3621 | 1454.9 | 652.3 | 907.6 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 304 | `c6f5b0b8` | `GET /modules/jeevika-jankar-payment-list-detail` | 200 | 1298 | 220.6 | 90.7 | 246.8 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 309 | `291812a0` | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 109 | 78.9 | 18.7 | 41.9 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 314 | `594b3974` | `GET /jj-quizzes` | 200 | 108 | 27.5 | 52.8 | 1.6 | Reviewed; no additional code-specific bottleneck established from this request. |
| 318 | `3b9bb1c0` | `GET /dashboard` | 200 | 8983 | 40.8 | 386.2 | 1526.4 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 322 | `c9b984c1` | `GET /logout` | 302 | 3 | — | 0.0 | 0.5 | Reviewed; no additional code-specific bottleneck established from this request. |
| 326 | `36c1083f` | `GET /login` | 200 | 22 | 14.8 | 3.2 | 4.7 | Reviewed; no additional code-specific bottleneck established from this request. |
| 330 | `0aecde7e` | `POST /login` | 302 | 19 | — | 11.4 | 1.7 | Reviewed; no additional code-specific bottleneck established from this request. |
| 335 | `a67d277a` | `GET /dashboard` | 200 | 8371 | 54.4 | 410.9 | 1422.2 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 339 | `92f33cf6` | `GET /` | 302 | 6 | — | 1.5 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 343 | `e4b45fb4` | `GET /dashboard` | 200 | 1175 | 66.4 | 496.6 | 133.3 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 347 | `ef10c71d` | `GET /users/new` | 200 | 10753 | 368.3 | 236.8 | 2765.9 | Shared field readers avoid unused aliases; original values/fallbacks retained. Cold form/location cache build remains. |
| 351 | `f4c6eb3c` | `GET /vrps/new` | 200 | 11599 | 8939.5 | 2353.1 | 3928.4 | Shared field readers avoid unused aliases; original values/fallbacks retained. Cold form/location cache build remains. |
| 356 | `b53d550d` | `GET /vrps` | 200 | 4301 | 13.2 | 67.0 | 1138.2 | Reviewed; no additional code-specific bottleneck established from this request. |
| 360 | `b2d00d6e` | `GET /modules/approval-list` | 200 | 96 | 66.8 | 9.0 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 365 | `1ebabcc4` | `GET /target_mappings` | 200 | 423 | 62.4 | 54.5 | 214.1 | Reviewed; no additional code-specific bottleneck established from this request. |
| 369 | `f7b9a660` | `GET /target_mappings/vrp_mappings` | 200 | 38 | 0.2 | 27.1 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 373 | `e45b725b` | `GET /modules/training-form-list` | 200 | 20704 | 10.5 | 111.5 | 5177.5 | Indexed legacy owner fallback; original pending/latest rules retained. Production residual timing unverified. |
| 378 | `c7a3dca9` | `GET /modules/jeevika-jankar-bill-list` | 200 | 5611 | 504.1 | 192.7 | 1391.1 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 383 | `df16292e` | `GET /modules/jeevika-jankar-payment-list` | 200 | 2714 | 1452.1 | 296.0 | 489.2 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 388 | `6c5ca6df` | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 1856 | 1800.3 | 45.5 | 555.6 | Shared field/legacy-owner reads improved where used; existing financial rules retained. Full bill calculation/render cost not proven resolved. |
| 393 | `607c7beb` | `GET /` | 302 | 2 | — | 0.0 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 397 | `08354456` | `GET /dashboard` | 200 | 1118 | 68.2 | 359.0 | 193.4 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 401 | `b8c8dac0` | `GET /dashboard` | 200 | 1248 | 53.3 | 558.4 | 111.4 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |
| 405 | `b4f1f4cf` | `GET /logout` | 302 | 2 | — | 0.0 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 409 | `7f4a55d3` | `GET /login` | 200 | 5 | 4.0 | 0.0 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 413 | `bd90266f` | `POST /login` | 302 | 18 | — | 12.8 | 0.0 | Reviewed; no additional code-specific bottleneck established from this request. |
| 418 | `00a4fe2d` | `GET /dashboard` | 200 | 1346 | 49.1 | 499.8 | 293.7 | Shared field/owner helpers improved where used; scope and aggregation rules retained. Full dashboard CPU/GC still requires post-deploy measurement. |

## Every slow-SQL marker

| Request ID | SQL ms | Logged source | Disposition |
|---|---:|---|---|
| `3788b591` | 1646.4 | `app/controllers/modules_controller.rb:16484` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `08bd6dd1` | 1680.2 | `app/controllers/modules_controller.rb:16460` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `1dc80a75` | 7345.4 | `app/controllers/modules_controller.rb:16460` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `1dc80a75` | 819.2 | `app/controllers/modules_controller.rb:16923` | Scalar dropdown result now revision-cached; cold SQL retained. |
| `e7b0c2f1` | 768.7 | `app/controllers/modules_controller.rb:16424` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `e7b0c2f1` | 5274.5 | `app/controllers/modules_controller.rb:9731` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `b725dd1e` | 1477.4 | `app/controllers/modules_controller.rb:16923` | Scalar dropdown result now revision-cached; cold SQL retained. |
| `da79b4f8` | 3355.3 | `app/controllers/modules_controller.rb:16923` | Scalar dropdown result now revision-cached; cold SQL retained. |
| `7a19372d` | 1480.7 | `app/controllers/vrps_controller.rb:2105` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `bfd77738` | 1874.2 | `app/controllers/modules_controller.rb:16923` | Scalar dropdown result now revision-cached; cold SQL retained. |
| `76a4db3b` | 1399.2 | `app/controllers/modules_controller.rb:9467` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `b600fb36` | 1252.2 | `app/controllers/modules_controller.rb:9467` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |
| `1618efb2` | 1353.2 | `app/controllers/modules_controller.rb:16923` | Scalar dropdown result now revision-cached; cold SQL retained. |
| `f4c6eb3c` | 1342.8 | `app/controllers/vrps_controller.rb:2105` | Existing cold projection/revision read retained; no production query plan/wait profile supplied. |

## Remaining limits and existing checks

This is not an all-issues-fixed claim. Cold location projection queries, full catalogue hydration/building, financial/report calculations, external API waits and production CPU/memory/DB contention have not all been eliminated or timed after deployment. The logs do not contain full SQL text, database plans, lock waits, host memory/swap or CPU profiles. Office List and JJ Mapped Farmers code explicitly waits for external APIs; this patch retains live-data behavior rather than silently changing freshness or timeout semantics.

The ten remaining baseline checks concern grouped attendance (one), training visibility/absent request state (three), saved contact fallback (one), aggregate query-count expectation (one), incomplete API VRP fixture (one), location-cache request setup (one), and photo naming/upload acceptance expectations (two). They include test setup/expectation problems and potential functional issues; they are not ten proven production defects. No financial, permission, attendance or upload policy was silently changed to force those tests green. See the earlier audit for their exact names.

No universal 3–5 ms response claim is made. Post-deployment authenticated logs and runtime measurements are still needed to quantify full-page improvements and isolate residual delays.
