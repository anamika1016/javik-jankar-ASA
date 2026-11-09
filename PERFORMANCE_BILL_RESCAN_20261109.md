# Bill-list follow-up: latest ddfa1c2e log

Scanned all 123 completed request entries in the supplied log and correlated request IDs with routes. Bill list took 8,044 ms (views 7,193.9; database 633.0; GC 1,654.4) and 5,200 ms (views 471.3; database 222.4; GC 957.2). These timings do not support attributing the entire delay to SQL. Other slow requests include training list 18,561 ms, users/new 12,778, LG directory 11,352, VRP new 11,176 and dashboard 10,090. GC and request durations can overlap; the numbers must not simply be added or treated as proof of host contention.

Changed `jeevika_bill_prepared_by`: the mapped CC name and saved creator name already have priority over user/module-record/JJ identity fallbacks. If either is a valid display name, return the same name and timestamp without fetching unused fallback identities. Blank, dash, null and nil labels retain the old fallback rules. Approval history and timestamp precedence remain unchanged. No approval, visibility, mutation, amount or target rules were edited.

Verification: 73 Rails tests / 575 assertions passed, covering prepared-name precedence/fallbacks, populated bill row parity, billing page scaling, approval channels, mutation redirects, dashboard reports and training approvals. New tests raise if unused identity fallbacks execute for a valid primary name. `git diff --check` passed.

This local change removes unnecessary identity work. It is not a measured production speedup and does not resolve all unexplained request time in the new log. No production deployment, authenticated browser trace, production CPU/memory profile or database wait inspection was performed. Existing navigation fixes are already committed in the current checkout; they were not reimplemented here.

## Broader follow-up

Inventoried all available journal attachments: 68 files / 10,319 completed entries, including historical and overlapping excerpts. These are not distinct current requests and their maxima must not be presented as current deployment latency. The latest supplied log remains the 123-entry ddfa1c2e excerpt discussed above.

Target-mapping entry dropdowns still instantiated ModuleRecord objects merely to choose labels from a small JSON projection. They now pluck JSON arrays directly. Exact case-sensitive active-status predicate, first-present-field precedence, source order, JSON value types and Ruby uniqueness are retained. Empty field lists and symbol keys retain their previous empty results. No writes or permission changes were added.

New test compares old-style record-based output against projected output for false/blank fallbacks, zero, arrays, objects, duplicates and inactive labels; it verifies zero model instantiation notifications for the optimized read. Latest focused suite: 74 tests / 579 assertions, zero failures/errors. Diff check passed. This reduces allocation work on target entry pages, not proof that every slow route in historical logs is fixed.

## Combined behavior rescan

145 Rails tests / 1,028 assertions passed across cache invalidation, bill names/rows, approvals, mutation redirects, dashboard reports/drilldowns, monthly training reads, target dropdowns, location rendering and user/VRP forms. Ten JavaScript navigation/action/rendering test files passed. No new regression was found in this selected combined run; previously documented broader baseline failures are not thereby resolved. No further business-rule change was made during this review. Production request time outside the measured SQL/view work remains unexplained and needs runtime profiling; the combined test run is not production performance evidence.
