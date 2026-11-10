# 10 November: new production logs and request CPU fixes

Baseline: `c480b27`. The new attachment contains 90 unique completed request IDs: 82 HTTP 200 and eight HTTP 302. A later complete rescan also identified four RoutingErrors without Completed events; see PERFORMANCE_REQUEST_RESCAN_20261110.md. Thirty take over one second. Duplicate pasted entries were counted once by request ID.

The worst reads include user new (9,989 ms), JJ new (9,167 ms), other-target-with-farmer (8,582 ms), other-target (8,477 ms), bill list (7,984 ms), external JJ catalogue (7,392 ms), target mappings (5,759 ms), JJ edit (5,467 ms), approvals (3,767 ms), dashboard (3,119 ms). These are pre-patch production measurements, not post-patch claims.

Stage evidence: user form options allocate about 6.77 million objects and consume 8.4–8.9 seconds process CPU; JJ location attributes allocate about 6.91 million objects, returning 8,782,251 escaped bytes. Staff bill reads allocate about 4.68 million objects; staff training visibility about 1.06 million. Process counters may include overlapping Puma threads. The external JJ catalogue's 7.3 seconds includes only about 104 ms process CPU, so these CPU fixes cannot remove that external wait.

## Changes

- User create/update no longer build all master dropdowns and the location catalogue on a successful save. All four password/model-validation failure branches still load the original complete options before rendering; new/edit continue to load them.
- User location-row alias keys are constructed once rather than allocating the same 22-key array and its strings for each row. User/module row builders read each alias value once and preserve all aliases, trimming, overrides, ordering and identifiers.
- User/module/JJ active/deleted checks avoid constructing a four-string array on every flag check and skip conversion of absent/false flags. JSON flag results and status behavior are preserved.
- Module/dashboard and JJ name normalization and fuzzy matching reuse pure results within the current controller request. Both true and false matches are cached. Keys are copied, normalized strings remain independently mutable, and each cache is bounded at 4,096 entries. No user scope or authorization result is cached across requests. The existing exact/fuzzy/role-suffix matching algorithm is unchanged.

DashboardReportsController inherits ModulesController, so shared normalization improvements apply there too. This patch does not remove the dashboard's remaining SQL work.

## Before/after measurement

`script/benchmark_request_cpu.rb` loads original methods from the baseline into subclasses and compares complete outputs. Local isolated test DB, generated 20,000-row workload, no database writes:

| Workload | Before | After | Objects before → after |
|---|---:|---:|---:|
| Complete cold user form payload | 450.89 ms | 277.13 ms | 2,454,701 → 1,280,437 |
| 20,000 repeated module label comparisons | 391.96 ms | 26.40 ms | 1,936,005 → 102,612 |
| Same JJ comparison workload | 388.85 ms | 27.31 ms | 1,936,004 → 102,612 |

Complete user form payloads and comparison outputs matched. These are synthetic CPU timings, not HTTP, actual production data, or a promise of equal speedup on every page. Pure matching reuse benefits repeated labels; lists consisting entirely of new label pairs benefit less.

## Verification

63 tests / 1,204 assertions passed, zero failures/errors: new cache parity/mutation/bounds tests, successful user saves without catalogue queries, all four error form renders, cold/warm authenticated forms, escaping/invalidation, JJ form reads, bill staff scope, cluster mappings and bill read/channel caches.

Additional checks exposed existing failures: module lookup office visibility and bill totals; training visibility similar-name expectation and two nil-request fixtures. Restoring every changed ModulesController method from Git in memory reproduced the same five failures/errors (20 tests, three failures/two errors). The separate location catalogue suite also has an existing mock request without `filtered_parameters`; it reproduced before edits. These remain unresolved; the full application suite is not declared passing.

No production deployment or production browser measurement was performed. Full pages include HTML transfer, browser parsing and external/SQL waits. The 8.8 MB location attribute alone means a universal maximum 5 ms page-open guarantee is not supported. This change preserves complete dropdown payloads and existing behavior; reducing that payload through lazy loading would need separate behavior-aware design and validation. Deploy/restart and compare fresh request-ID stage logs to establish actual production gains.
