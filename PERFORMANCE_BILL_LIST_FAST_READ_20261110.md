# Bill List fast-read follow-up — 10 November

The Bill List changes are present in commit `242c1b5` (subsequent Farmer App work is separate). No production deployment or production HTTP latency measurement was performed in this task.

## Confirmed changes

- Removed repeated full-target ID sorting from target completion reads. A complete achievement index now distinguishes a real missing entry from a partial caller index. Partial/absent indexes retain their old authoritative fallback, and missing achievements retain the old saved-bill fallback and cap.
- Bill totals reuse the achievement index already loaded for their exact owner/month candidate set. Previously the same full candidate key was sorted again inside the per-target loop. This also benefits the shared dashboard/payment calculations.
- Approval-channel selection visits only matched channels. Original catalogue order is retained even when a later step is the first matching step, preserving priority ties and approval rules.
- Active Bill List status filters run against the same calculated workflow labels before live totals. Pending remains the complement of final-approved, including submitted/rejected/returned bills. The original final row filter remains in place. Admin unfiltered reads still include every original row; client search/export, selection, actions and pagination are unchanged.
- Favicon HTML uses the configured Stakeholder Master logo, with existing stakeholder/profile fallback precedence. A live tuple revision invalidates cached branding after edits, including direct updates preserving timestamps. When no logo is configured, existing `/icon.png` is the fallback; missing `/jj_logo.png` is no longer referenced.

## Full HTML comparison

Local isolated PostgreSQL, generated 150 bills and 450 target mappings, two sequential cold/warm reads, external HTTP disabled, all synthetic writes rolled back. Original calculation methods and, for the filtered comparison, original view/candidate filtering were restored from `c480b27` in a separate process. Shared unrelated request CPU optimizations were present in both runs. No profiler instrumentation was enabled for these timings.

| Full Bill List HTTP render | Before | After | Allocations before → after |
|---|---:|---:|---:|
| Unfiltered, cold | 344.20 ms | 264.73 ms | 637,279 → 364,265 |
| Unfiltered, warm | 295.55 ms | 206.79 ms | 596,867 → 323,913 |
| Pending filter, cold | 335.02 ms | 181.80 ms | 633,413 → 199,377 |
| Pending filter, warm | 284.50 ms | 98.45 ms | 592,794 → 159,618 |

For the filtered workload, 50 of the 150 bills are submitted/pending-bucket records; the remainder are final approved. Complete rendered text, input/select/button controls and browser `data-*` action attributes had identical SHA-256 hashes before/after for every corresponding pass. Response byte counts also match in the filtered comparison. Query counts can rise slightly when filtered status decisions need identity/history resolution before narrower total calculations; the measured gain is reduced CPU/allocation work, not a claim that every SQL count drops.

A separate instrumented small profile originally called the achievement-index reader 164 times across two requests. It exposed repeated candidate-key construction as a CPU cost. Instrumented timings are not mixed into the full HTTP table above.

## Behavior verification and limits

The focused suite passed **60 tests / 628 assertions**, zero failures/errors. After the independent Farmer OTP schema changes and restoring the isolated test schema, a fresh rerun again passed **60 tests / 628 assertions**, zero failures/errors. It covers complete/partial index misses, caps and saved-bill fallback; pending/final status semantics; approval-channel catalogue-order ties; live bill row parity across month/state filters; admin/staff and scoped totals; numeric-month fallbacks; approval history/resubmission; and Stakeholder Master favicon updates with a warm process cache.

The broader controller/service run was interrupted without a completion summary; it is not declared passing. Previously documented baseline failures remain. A verification rerun after the workspace's Farmer OTP schema updates initially hit a PostgreSQL template encoding problem during automatic schema refresh. The isolated test database was recreated with UTF-8/template0 and its current schema loaded; the rerun then passed. Farmer OTP application files were not edited by this performance continuation.

These results demonstrate local millisecond response times, not a universal 5 ms page-open guarantee or a measured production speedup from the old 8-second log. Cold SQL, external API waits, long complete-row lists and browser/network transfer still need post-deploy measurement. No business visibility, approval, payment or export rule was deliberately changed to claim a lower time.

## Final behavior rescan

Rechecked the performance-only source diff against `c480b27`, including request-local label caching, saved location batching, user save/error form loading, complete-versus-partial achievement indexes, approval-channel catalogue ties, pre-total workflow filtering and favicon cache freshness. Independent Farmer App/OTP edits in the workspace were left untouched.

Added real persisted approval-history coverage: a stored Pending bill whose final step was approved enters the final-approved filter; after a Bill Edited boundary and draft reset, the old approval no longer puts it in that bucket. Expanded live-row comparison to 27 month/state/status combinations with mixed pending/final records, comparing complete row hashes including paths and live target/achievement totals against generating all rows then applying the original filters.

Latest combined check: **69 tests / 1,531 assertions, zero failures/errors**. Diff whitespace checks pass. No new logic mismatch was detected in these tested paths, and this rescan required no further application-code changes. Previously documented broader baseline failures and unmeasured production latency remain; this is not a claim that every application path or concurrent production scenario has been proven correct.
