# Progress lifecycle follow-up — 9 November 2026

Public production assets contain the previous navigation_progress implementation (downloaded module matches the local original). This is not evidence of an authenticated dashboard reproduction: browser access to the user's session was unavailable.

This patch makes progress cleanup an independent module entry in the application layout. A failed download/link in the large application module graph can otherwise prevent the cleanup module from executing too. Login retains its existing standalone entry. This is startup hardening; the screenshot's exact cause is not established.

A cancelled/failed visit can leave a cached preview without a final render. Cleanup now preserves previews only while their visit is actually initialized/started, and rechecks idle state after a fetch error. A still-active visit keeps its indicator. Requests, redirects, submissions and the preview DOM are not cancelled or replaced by this patch.

No backend business rules, approvals, permissions, amounts or mutation handlers were edited. This does not establish equivalence of every historical change.

Validation: assets compiled; 31 focused Rails tests / 177 assertions passed (compiled loader serving, billing row parity, bill mutation redirects, training approval service). JavaScript navigation completion regression passed, including a cancelled preview and an active visit after a fetch error. Broad JavaScript run: 15 of 16 files passed; unchanged language_switch_test.cjs fails because its mock lacks document.getElementById. Both that test and layout.js match HEAD. git diff --check passed.

Latest supplied e57f9f94 log: inspected all 109 completed requests and correlated request IDs. Slowest bill list 54,215 ms (also 40,870 and 37,809); training list 17,986; payment list 13,997; block master 12,915; LG directory 12,483; village master 11,705; dashboard 11,640; VRP new 11,107. These production bottlenecks remain unresolved by this frontend patch. Production CPU/memory/database wait profiling and authenticated request tracing are still needed to attribute them. No universal 5 ms page latency is verified or promised.

No production deployment was performed. Deploy matching compiled production assets with this source change. The current local test results do not verify the live screenshot is resolved.

## Backend follow-up

Scanned all seven supplied attachment logs, correlating request IDs: 425 completed entries including repeated copies/excerpts. Per-file completed counts: df4dbfdf 26; 1a998f90 52; e3880c89 78; 38418203 30; eb4802c5 100; 2b88790c 30; e57f9f94 109. Local machine-readable results are in `tmp/performance_log_rescan_20261109.json`; missing request starts are explicitly labelled rather than guessing their route.

Found a repeated CPU operation in billing/target progress: each target scanned all monthly training records, even for unrelated owners, before applying assignment, location and activity checks. Added a request-local index of the exact existing normalized owner aliases (ID, username, name, mobile and combined name/mobile). Blank owner metadata still matches every owner; missing target owners still return all candidates. Source order and duplicate positions are preserved. Existing final matching predicates still run. No cross-request stale-data cache or permission changes were introduced.

The index is used for target progress and both totals/detail billing paths. It reduces candidate matching work; it does not eliminate monthly source queries, approval version probes, unrelated page render costs or database/host contention. All old log durations predate this patch and cannot measure its production effect.

Regression checks: first run 86 tests / 710 assertions; second run 54 tests / 351 assertions, all passing. Coverage includes monthly training reads, dashboard reports/drilldowns, bill totals, payment/approval reads, location/user/VRP forms and training approval behavior. New tests compare all legacy owner aliases and blank fallbacks, preserve duplicates/order, and compare complete populated live bill rows against the previous full-month scan. For 50 owners and 200 training rows, source owner metadata is indexed once (200 reads versus 10,000 repeated reads). This is an operation-count result, not a measured 54-second-to-millisecond production speedup.

## Additional review

Extended owner candidate indexing to dashboard training selection when no farmer roll is assigned. The existing farmer-indexed path remains for nonblank rolls; the existing owner predicate and record-ID deduplication remain. A cache hit now returns before building candidates. New regression checks blank-owner fallback, unrelated-owner exclusion, identical cached result and one source read across repeated calls.

Latest rescan run: 90 Rails tests / 749 assertions passed; four JavaScript navigation/action regression files passed; git diff --check passed. No new failure was found in this selected suite. Previously documented broader baseline failures and unverified production latency remain; this is not a full-application or production certification.
