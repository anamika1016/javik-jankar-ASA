# November 16 production-journal hotspot fixes

Analyzed all 448 supplied lines and all 88 completed requests by request UUID. Baseline for this patch is `ed8203d`. Earlier improvements are committed in that baseline; the changes described here are the new follow-up.

## Correct attribution

Concurrent request lines had assigned several durations to the wrong pages in the supplied priority list. These are the actual requests, before this patch:

| Actual request | Total | Important evidence |
|---|---:|---|
| `/vrps/new` | 9,388 ms | `vrp.location_attribute` 7,793 ms; GC 2,571 ms |
| `/modules/district-master` | 8,610 ms | Views 7,155 ms; DB 1,429 ms |
| `/modules/village-master` | 8,202 ms | `module_records` 7,384 ms |
| `/modules/lg-directory-list` | 8,197 ms | Directory build 6,889 ms, about 2.93 million process allocations |
| `/users/new` | 7,801 ms cold; 691 ms later | Form options 7,040 ms cold |
| `/modules/block-master` | 7,619 ms | Full master read SQL 4,109 ms |
| `/target_mappings/jj_user_options` | 7,096 ms | External catalogue 7,090 ms |
| `/dashboard` | 6,075 ms | DB 3,983 ms; latest-revision SQL 2,967 ms |
| `/modules/training-form-list` | 5,669 ms | Visibility 3,911 ms; total record preparation 5,382 ms |
| `/modules/jeevika-jankar-bill-list` | 4,842 / 4,784 ms | Views 4,445 / 4,026 ms |
| `/modules/month-master` | 4,538 ms | DB 4,093 ms; source/options reads |
| `/vrps` | 4,114 ms | Low reported DB/view time; GC 941 ms |
| `/vrps/approvals` | 3,392 ms | Low reported DB/view time; GC 793 ms |
| `/modules/jeevika-jankar-payment-list` | 3,377 / 3,120 ms | DB + view/GC work |
| `/modules/jeevika-jankar-payment-list-detail` | 2,538 ms | DB 1,818 ms |
| `/modules/other-target-with-farmer` | 611 ms | The 7,096 ms entry belongs to the separate JJ catalogue request |
| `/modules/stakeholder-master` | 23 ms | Not the request taking 8.2 seconds |

GC/process CPU stages can overlap other work and other threads. Do not add them to SQL/view totals. These logs show two Puma workers and interleaved requests; host memory/CPU/PG wait measurements are needed to distinguish additional contention. The source trace does establish repeated expensive source reads and cold cache fills.

## Implemented changes

### Fast source versions, including direct SQL/imports

Migration `20261116120000_add_module_record_read_versions.rb` installs a small version table, a sequence and four PostgreSQL statement triggers (INSERT, UPDATE, DELETE and TRUNCATE). Each affected module receives a new sequence stamp in the same transaction. Update/move statements cover both old and new slugs; imports and `update_all`, `update_columns`, `delete_all` and raw SQL do not depend on Rails callbacks. Business records and their timestamps are not modified by the tracking triggers.

Warm catalogue checks now read the relevant small module stamps instead of repeatedly aggregating/sorting `id`, `xmin` and `ctid` over every source row. Global readers hash module stamps rather than source records. There is deliberately no shared global counter row to serialize writes to unrelated modules.

Sequence values are not reused after rollback. A value published by a request inside a subsequently rolled-back transaction cannot collide with a later different update. A random migration epoch also separates recreated tracking tables from older cache keys.

The new path is used by module dropdowns, module/VRP location catalogues, user form options, bill summary versions and training revision ID caching. The latest-revision rule, exact reference strings, approval statuses, visibility predicates and selected payload values remain unchanged. Training cold fills still run a fresh final source check before publishing.

Readers verify all four enabled triggers and an epoch. Missing migration/table, missing/disabled triggers or an uninitialized schema-only restore retain the old fingerprint path. Normal imports must keep these tracking triggers enabled. Database-owner operations that deliberately bypass triggers require rebuilding tracking metadata and prewarming before relying on it again.

### Avoid repeated cold preparation across workers

Dropdown values and bill summary attributes now use the existing optional, version-guarded shared catalogue cache as well as process RAM. These are the same raw/scoped-source payloads used previously; user authorization and approval/owner filters still run on each request after reading them. Callers get independent arrays/data objects. Direct edits invalidate them immediately through the source stamp. Shared-cache code fingerprints include the version reader and dropdown cache implementation.

The prewarm script now also covers training revision IDs, bill summaries and common location/month/activity dropdowns. This moves their cold SQL/JSON work into an explicit release preparation step rather than the first visitor after restart/import. This does not eliminate cold work after every possible later source change.

### Visibility and diagnostics

Repeated exact cluster-ID membership checks now use a request-local Set instead of scanning the same large array for every training, target and bill. ID strings, leading zeroes, negative cases and source ordering are unchanged; the original array is retained. The expensive bill row builder additionally emits a `bill.rows` stage so a future production trace can separate row preparation from template output.

No frontend, bill amount, approval decision, save rule or permission predicate was changed in this patch. An attempted projection for master sorting failed the existing pagination regression because legacy sorting can depend on original JSON insertion order. That experiment was removed; full original sorting behavior was retained.

## Measured local results

Synthetic isolated PostgreSQL fixtures, HTTP disabled, writes rolled back. These are individual preparation stages/batches, not production full-page latency or a concurrency benchmark. The mixed latest-revision fixture includes nonempty blocked-training results.

| Case | Before | After | Compared result |
|---|---:|---:|---|
| 20 global version checks, 28,000 source rows | 184.37 ms | 6.42 ms | No source-row scan after change |
| Warm Month dropdown preparation | 10.05 ms | 1.38 ms | Equal |
| 20 warm latest-training-revision reads | 17.57 ms | 8.82 ms | Equal |
| 5,000 membership checks against 15,000 cluster IDs | 258.27 ms | 5.01 ms | Equal |
| User catalogue, 8,000 villages: cold vs prewarmed fresh worker | 282.41 ms | 11.04 ms | Equal payload |

## Validation

- Focused checks: **242 tests, 1,604 assertions, zero failures/errors**.
- Complete Ruby suite, including unchanged helpers/models: **961 tests, 8,318 assertions, 23 failures + 9 errors**. The same 32 failing/error test names appear in the previous baseline run; no new names appeared. This suite is not green.
- Fresh cold/warm render audit: **46/46 return 200**. Compared with the preceding run, 42 render signatures match; four `/vrps` and `/vrps/approvals` snapshots contain changed generated-ID-dependent signatures between fixture runs. They are not claimed as exact byte-equality proofs. Relevant ID/label/visibility regression tests pass.
- Fresh role audit: **329 requests** — 308×200, 9×401, 9×403, 2×302, 1×422; no 5xx/exceptions.
- Migration applied, rolled back and reapplied successfully on the isolated database. Source tests cover direct insertion/update/move/deletion, unchanged timestamps, TRUNCATE, savepoint rollback/nonreused stamps, unavailable table/disabled-trigger fallback and a source change during cold training-cache fill.
- Shared bill/dropdown tests compare the original projection, separate-worker-store reuse, caller-mutation isolation and immediate direct-update freshness. Existing cache tests cover actual forked process locking and source-edit race protection.
- `performance:prepare` and all 18 warm tasks execute successfully on the isolated database. Ruby/Rake syntax and `git diff --check` pass. No JavaScript or views were changed in this follow-up.

Query-count tests were adjusted to count the new version-table probes separately from source-payload reads. Their output/ordering/visibility assertions were retained.

## Apply to production

No production migration, deployment, restart or latency test was performed here. After deploying this patch, run from the active release as the same application user before sending traffic to the new workers:

```sh
RAILS_ENV=production bundle exec rails performance:prepare
sudo systemctl restart javik
```

`performance:prepare` runs migrations, checks that tracking is available, then prewarms shared data. Running only a restart without the migration keeps the legacy scan path. Running without prewarm can still make the first visitor pay the cold-build cost. Run on each application host, with the same active release/cache directory and environment as Puma.

Ruby `schema.rb` does not preserve PostgreSQL functions/triggers/sequence data. After a schema-only restore, or for a schema-loaded test database, initialize this optional tracking feature with:

```sh
RAILS_ENV=production bundle exec rails db:migrate:redo VERSION=20261116120000
RAILS_ENV=production bundle exec rails performance:prepare
```

Use `RAILS_ENV=test` and the isolated test `DATABASE_URL` for the equivalent test setup. The redo affects tracking metadata only, not business rows, and changes the epoch to reject old keys. The prepare task refuses to silently claim success when tracking is unavailable. Keep SQL functions/triggers when doing a full PostgreSQL backup/restore.

After rollout, collect the same pages under real traffic and the existing runtime diagnostic:

```sh
bash script/performance_runtime_snapshot.sh javika_production 6
```

The 7.1-second external JJ catalogue and 3.9-second external Office List response are still upstream waits. Their initial navigation is already separated into frames; these fixes do not make the remote server respond in 15 ms. Large bill-row/template output, browser rendering, transfer time and host contention can also remain significant. The added bill stage helps measure the remaining view hotspot. No maximum 5–15 ms complete-page guarantee is established, and this patch is not evidence that every production bottleneck is eliminated.

Artifacts: `tmp/performance_logs_20261116.json`, `tmp/nov16_request_hotspot_audit.json`, `tmp/nov16_focused_tests.log`, `tmp/nov16_all_tests.log`, `tmp/nov16_render_audit.json`, `tmp/nov16_role_audit.json`, `tmp/nov16_prepare_smoke.log`, `tmp/nov16_revision_migration_redo.log`.

## All 88 requests

Original production timings before this patch. Journal start/end line numbers identify interleaved requests without reproducing query parameters or IPs.

| Request | Total ms | DB ms | Views ms | GC ms | Start/end lines |
|---|---:|---:|---:|---:|---|
| `/vrps/new` | 9388.0 | 2020.1 | 7055.1 | 2570.5 | 196/227 |
| `/modules/district-master` | 8610.0 | 1428.5 | 7155.1 | 1981.6 | 42/65 |
| `/modules/village-master` | 8202.0 | 1502.2 | 637.1 | 1798.1 | 51/99 |
| `/modules/lg-directory-list` | 8197.0 | 1506.9 | 659.7 | 1504.5 | 33/56 |
| `/users/new` | 7801.0 | 192.4 | 715.9 | 2101.4 | 156/175 |
| `/modules/block-master` | 7619.0 | 5431.7 | 683.5 | 2002.3 | 45/68 |
| `/target_mappings/jj_user_options` | 7096.0 | 35.9 | 4.2 | 0.0 | 239/270 |
| `/dashboard` | 6075.0 | 3983.4 | 84.5 | 539.0 | 20/24 |
| `/modules/training-form-list` | 5669.0 | 1456.2 | 274.4 | 467.3 | 371/400 |
| `/modules/jeevika-jankar-bill-list` | 4842.0 | 274.0 | 4444.8 | 745.7 | 333/337 |
| `/modules/jeevika-jankar-bill-list` | 4784.0 | 519.1 | 4025.9 | 562.1 | 283/302 |
| `/modules/month-master` | 4538.0 | 4093.1 | 132.3 | 929.7 | 57/79 |
| `/vrps` | 4114.0 | 83.7 | 18.6 | 941.1 | 348/357 |
| `/modules/office-list` | 3950.0 | 0.0 | 9.6 | 19.0 | 117/125 |
| `/vrps/approvals` | 3392.0 | 50.6 | 15.5 | 792.6 | 352/359 |
| `/modules/jeevika-jankar-payment-list` | 3377.0 | 725.3 | 1867.1 | 772.3 | 385/402 |
| `/vrps/approvals` | 3241.0 | 35.3 | 36.9 | 520.1 | 203/209 |
| `/modules/jeevika-jankar-payment-list` | 3120.0 | 606.3 | 1941.0 | 455.9 | 293/309 |
| `/dashboard` | 2973.0 | 1252.9 | 47.6 | 463.6 | 436/439 |
| `/modules/add-activity-group` | 2856.0 | 2804.5 | 47.1 | 5.0 | 131/146 |
| `/modules/gram-panchayat-master` | 2547.0 | 121.2 | 139.2 | 808.7 | 69/76 |
| `/modules/jeevika-jankar-payment-list-detail` | 2538.0 | 1818.1 | 192.0 | 412.7 | 298/312 |
| `/modules/jeevika-jankar-bill-list` | 2356.0 | 859.0 | 471.6 | 487.7 | 381/393 |
| `/target_mappings` | 2163.0 | 42.0 | 1788.9 | 394.7 | 228/234 |
| `/dashboard` | 2121.0 | 522.1 | 47.8 | 416.4 | 415/418 |
| `/modules/training-form-list` | 1979.0 | 1787.0 | 164.0 | 0.0 | 246/260 |
| `/modules/training-form` | 1888.0 | 1409.9 | 476.5 | 31.7 | 243/251 |
| `/modules/other-target-list` | 1591.0 | 35.3 | 17.4 | 106.7 | 374/380 |
| `/target_mappings/list` | 1581.0 | 19.8 | 1057.3 | 367.8 | 230/242 |
| `/vrps/new` | 1447.0 | 873.4 | 278.5 | 182.8 | 346/351 |
| `/dashboard` | 1215.0 | 646.1 | 71.1 | 92.7 | 29/32 |
| `/dashboard` | 920.0 | 563.3 | 34.7 | 36.7 | 445/448 |
| `/vrp-agreements` | 735.0 | 681.6 | 14.0 | 134.0 | 354/364 |
| `/users/new` | 691.0 | 82.7 | 429.9 | 135.5 | 342/345 |
| `/modules/approval-master` | 626.0 | 603.4 | 21.0 | 92.0 | 205/211 |
| `/modules/jeevika-jankar-completed-payment-list` | 618.0 | 92.6 | 514.3 | 53.7 | 389/396 |
| `/modules/other-target-with-farmer` | 611.0 | 80.6 | 528.3 | 215.8 | 266/272 |
| `/vrp-agreements` | 519.0 | 324.1 | 116.4 | 19.1 | 217/220 |
| `/modules/role-name` | 449.0 | 394.1 | 50.6 | 43.6 | 93/104 |
| `/modules/jeevika-jankar-bill-process` | 410.0 | 340.5 | 15.1 | 18.7 | 278/282 |
| `/vrps` | 327.0 | 40.8 | 53.7 | 19.3 | 198/201 |
| `/modules/other-target-list` | 317.0 | 10.1 | 270.3 | 36.6 | 261/265 |
| `/` | 295.0 | 31.3 | — | 91.8 | 16/19 |
| `/modules/other-target` | 286.0 | 66.1 | 218.2 | 82.5 | 252/256 |
| `/modules/user-hierarchy-list` | 282.0 | 10.6 | 264.0 | 95.4 | 163/167 |
| `/farmer-news` | 266.0 | 76.7 | 171.7 | 0.8 | 325/328 |
| `/modules/state-master` | 265.0 | 95.7 | 154.0 | 14.8 | 37/41 |
| `/` | 233.0 | 26.5 | 165.9 | 67.1 | 12/15 |
| `/modules/parent-office-add` | 183.0 | 144.5 | 33.7 | 0.0 | 88/97 |
| `/modules/other-target-with-farmer-list` | 172.0 | 11.6 | 122.1 | 27.5 | 273/277 |
| `/modules/office-mapping-add` | 148.0 | 86.6 | 54.4 | 6.8 | 107/111 |
| `/modules/office-category-add` | 146.0 | 102.8 | 38.3 | 0.0 | 100/106 |
| `/modules/jeevika-jankar-transfer` | 138.0 | 12.6 | 122.6 | 64.6 | 169/173 |
| `/users` | 108.0 | 64.5 | 41.0 | 1.0 | 338/341 |
| `/modules/approval-list` | 104.0 | 6.5 | 80.4 | 7.5 | 212/216 |
| `/jj-quizzes` | 99.0 | 32.8 | 23.9 | 0.5 | 313/316 |
| `/farmer-app-logins` | 98.0 | 49.9 | 19.6 | 0.3 | 321/324 |
| `/afls` | 95.0 | 12.7 | 78.7 | 12.9 | 221/224 |
| `/farmer-videos` | 89.0 | 21.8 | 30.3 | 18.4 | 329/332 |
| `/modules/add-vrp-activity` | 78.0 | 8.3 | 64.4 | 25.3 | 139/143 |
| `/modules/access-control` | 78.0 | 14.2 | 62.1 | 5.3 | 181/185 |
| `/jj-mapped-farmers` | 70.0 | 18.7 | 17.7 | 6.5 | 367/370 |
| `/target_mappings/vrp_mappings` | 68.0 | 20.9 | 0.3 | 2.7 | 419/422 |
| `/asa360-mapping` | 64.0 | 17.7 | 22.9 | 3.6 | 120/123 |
| `/modules/jeevika-jankar-completed-payment-list` | 64.0 | 10.1 | 47.8 | 3.8 | 303/307 |
| `/modules/stakeholder-role` | 63.0 | 24.6 | 34.3 | 1.3 | 85/92 |
| `/modules/user-hierarchy-mapping` | 49.0 | 8.3 | 35.4 | 8.1 | 158/162 |
| `/users` | 45.0 | 7.0 | 34.3 | 2.2 | 152/155 |
| `/target_mappings/list` | 45.0 | 27.2 | 11.0 | 1.7 | 360/366 |
| `/modules/project-master` | 40.0 | 5.9 | 28.3 | 0.2 | 126/130 |
| `/modules/vrp-activity-list` | 37.0 | 3.5 | 27.8 | 2.3 | 147/151 |
| `/modules/access-control-list` | 24.0 | 3.4 | 16.2 | 0.0 | 186/190 |
| `/jj-mapped-farmers` | 24.0 | 3.5 | 15.7 | 0.0 | 235/238 |
| `/modules/stakeholder-master` | 23.0 | 3.0 | 15.6 | 2.2 | 80/84 |
| `/modules/jeevika-jankar-observation-list` | 23.0 | 7.4 | 9.8 | 0.1 | 288/292 |
| `/modules/activity-group-list` | 20.0 | 3.2 | 13.3 | 0.4 | 134/138 |
| `/farmer360` | 20.0 | 2.9 | 12.6 | 0.0 | 317/320 |
| `/login` | 19.0 | 5.2 | 11.5 | 0.2 | 407/410 |
| `/modules/jeevika-jankar-transfer-list` | 16.0 | 2.7 | 10.5 | 0.0 | 176/180 |
| `/modules/office-list` | 15.0 | 1.6 | 11.2 | 1.3 | 112/116 |
| `/modules/add-vrp-type` | 14.0 | 1.8 | 10.4 | 0.0 | 191/195 |
| `/login` | 10.0 | 2.7 | 5.7 | 0.3 | 427/430 |
| `/login` | 10.0 | 3.3 | — | 0.0 | 431/435 |
| `/login` | 9.0 | 3.1 | — | 0.6 | 440/444 |
| `/` | 6.0 | 1.5 | — | 0.0 | 25/28 |
| `/logout` | 3.0 | 0.0 | — | 0.0 | 403/406 |
| `/` | 2.0 | 0.0 | — | 0.0 | 411/414 |
| `/logout` | 2.0 | 0.0 | — | 0.0 | 423/426 |


## Additional behavior rescan

The follow-up review added two meaningful edge checks without changing application code: a single mixed bulk upsert must invalidate the old/new moved source and the newly inserted source while leaving an unrelated source unchanged; and two real database connections must permit unrelated module writes independently while keeping an uncommitted record/stamp invisible until commit. Both pass, including unchanged business timestamps and exact saved payload checks.

Repeated focused run: **244 tests, 1,620 assertions, zero failures/errors**, seed `14495` (`tmp/nov16_edge_review_focused.log`). Repeated complete Ruby suite: **963 tests, 8,334 assertions, 23 failures + 9 errors** (`tmp/nov16_edge_review_all.log`). The same 32 failing/error test names remain; none were added or resolved.

A source comparison also checked 22 relevant method bodies against the committed baseline, including create/update, validation normalization, saved-record loading, sorting, field lookup, bill totals/summary inputs, payment rows and approval decision/visibility methods. They match. The original bill-row body matches its new builder verbatim; its wrapper only adds timing instrumentation. Details are in `tmp/nov16_edge_review_method_parity.json`. The intentionally changed revision readers/cache plumbing and exact-ID membership optimization are covered by the separate regression cases, rather than being described as unchanged source.

`git diff --check` passes. No new application-code fix was needed in this rescan. Production rollout/latency verification and the existing full-suite failures remain outstanding; passing these cases is not a guarantee that every possible production workflow is issue-free.
