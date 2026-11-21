# Production CPU follow-up — 17 November 2026

## Evidence and remaining production limits

Reviewed the latest supplied Nov 16 journal (`f2cf71c6-9551-4356-9af6-e2093f79f0c9/Pasted text.txt`): 574 lines, 119 request IDs, 118 completed requests. Parsed evidence is in `tmp/performance_logs_latest_20261117.json`.

| Request | Total ms | Observed cost |
|---|---:|---|
| district-master | 14667 | Views 12098.8ms; GC 3875.3ms |
| vrps/new | 10185 | Location attribute stage 8282.9ms |
| block-master | 9161 | Views 8840.7ms |
| village-master | 8294 | module_records stage 7847.6ms for 15 displayed items |
| LG directory | 7819 | Build 6107.7ms; 2,928,402 allocations |
| users/new | 7473 | Form options 7073.3ms |
| external JJ catalogue frame | 7172 | External call 7164.7ms |
| gram-panchayat-master | 6584 | Views 4188ms |
| dashboard | 5822 | DB 3553ms |
| Bill List | 5350 / 5009 / 5027 | bill.rows repeatedly about 4.7 seconds for 280 rows |
| external office frame | 3409 | External call about 3366ms |

GC overlaps other timings; these columns must not be added together. The revision-reader and bill tracing paths are active in this journal. That does not establish whether the manual preparation task was run. A small revision query also took 1161.1ms: host/DB pressure requires server runtime evidence, rather than assuming every delay is an expensive SQL scan. No production RAM/swap diagnosis is established from these logs.

## Implemented changes

* Read-only catalogue caches now retain deeply frozen snapshots without Marshal reconstruction on every hit. Mutable request consumers retain their copies. The specialized store is limited to module location/LG, user form options and VRP location caches. LRU, expiry, versions and existing capacity limits remain. Capacity charges the retained object graph, which is larger than serialized bytes; this is not a claim that resident memory always decreases.
* Production Puma cluster startup prepares the catalogues once in the preloaded parent before workers fork. This removes competing first-request cold builds when preparation succeeds, and allows frozen graphs to benefit from copy-on-write. Actual server RSS savings have not been measured. Startup takes longer before workers are ready. Preparation failure logs a fallback and preserves normal cold reads. Single-process mode retains the manual preparation task. `PREWARM_CATALOGUES_ON_BOOT=0` disables automatic preparation.
* VRP eye/detail village lookup uses a revisioned minimal label index and hydrates only matching full records. It preserves aliases, Unicode/case handling, legacy value types, nested Hash label order, active/deleted filtering, ordering by creation date and complete selected-row attributes. Gram-panchayat fallback remains as before. Existing revision freshness guards remain; hydrated rows are checked again.
* Training matching rejects month, owner and location mismatches before resolving referenced assignments. The same AND predicates and topic/subject checks remain. The request-local owner candidate cache retains up to 1024 identities instead of 128, while retaining its existing 100,000-reference budget.
* The warmer includes the village detail index. No new migration, JavaScript, view, permission, save or payment calculation rule was introduced in this patch.

## Measured local gains

Reproduce with `RAILS_ENV=test bundle exec rails runner script/latest_catalogue_cpu_audit.rb` against the isolated performance test database. The script uses synthetic data and rolls back writes. These measure preparation stages, not production full-page latency.

| Stage | Before | After | Equality |
|---|---:|---:|---|
| Ten warm reads of 15,000-row snapshots | 124.44ms / 450,192 allocations | 0.12ms / 66 allocations | Same complete snapshot |
| Two selected villages out of 15,000 | 195.34ms / 15,000 model instances | 7.05ms / 2 model instances | Same ordered full attributes |
| 6,000 unrelated training checks | 259.35ms / 972,331 allocations | 64.23ms / 312,017 allocations | Same false outcomes |

For the snapshot fixture, accounted bytes changed from 1,383,794 serialized bytes to 4,728,852 retained graph bytes. Cache budgets are unchanged.

The recurring production Bill List 4.7-second calculation is not proven resolved by these measurements. An exploratory normalization cache did not consistently improve bill wall time and was removed. Derived payment totals were not cached across requests because freshness and permission dependencies need to remain correct. External JJ and office delays also remain dependent on the external service. No claim is made that every page now opens in 5–15ms.

## Verification

* Focused regression collection: **254 tests, 1,834 assertions, zero failures/errors**.
* Entire suite: **973 tests, 8,548 assertions, 23 failures and 9 errors**. All 32 failure/error identities match `tmp/nov16_edge_review_all.log`; no additional failures. The full suite is therefore not green.
* Synthetic render audit: **46/46 HTTP 200**. Role audit: **329 requests**, including 308 HTTP 200, nine 401, nine 403, two redirects and one 422; no server errors. External HTTP is disabled in these audits; they do not measure external service speed.
* New tests cover immutable snapshot identity, nested freezing, caller isolation, expiry/version/eviction, cycles, boot flags/fallback/Puma hook, actual form consumers, detail alias/type/deletion/order/freshness behavior and selected-only hydration. Matching parity checks compare original HEAD methods against the new implementation across 81 combinations, including referenced assignments.
* Changed/new Ruby files pass syntax checks; `git diff --check` passes.

## Production verification after deployment

This workspace patch has not been deployed or benchmarked on the server. After deploying the code, run the existing preparation task and restart:

```sh
RAILS_ENV=production bundle exec rails performance:prepare
sudo systemctl restart javik
```

For clustered Puma, verify `CATALOGUE_PREWARM completed` before workers begin serving. Compare first and repeated requests for Bill List, masters, LG, VRP new/detail, users and dashboard with the supplied journal. The preparation task also validates/applies existing migrations; this patch adds none.

Server runtime evidence remains requested using the existing read-only script:

```sh
bash script/performance_runtime_snapshot.sh javika_production 6
```

This will help distinguish CPU/GC, RAM/swap, process concurrency and DB waits. No server configuration or worker count was changed without that evidence.
