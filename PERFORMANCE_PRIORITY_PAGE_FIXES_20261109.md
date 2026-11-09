# Priority-page performance follow-up — 9 November 2026

Latest behavior rescan: **218 tests / 3,511 assertions; 208 pass, six failures and four errors match the original baseline**. One introduced edge was reproduced and fixed: calling `preload_user_form_module_records!` twice on the same controller could reuse sorted records from the old source. Reload now resets that request-local sorted cache. The regression failed before the fix and passes afterward; source edits are visible on reload again. Other examined HTML, ordering, cache freshness, permission and approval parity checks continue to pass. This does not clear the ten documented baseline checks or certify untested paths.

Changes are local and extend the fixes in `PERFORMANCE_NEW_LOG_FIXES_20261109.md`. No production deployment or authenticated production timing was performed. The supplied 20.7-second/11-second timings are not post-patch measurements.

## Additional changes

- Location option HTML on user/JJ forms is cached for lists of at least 100 entries, keyed by the exact options and selection. Order, selected/disabled values, HTML safety and escaping are retained; changed data immediately gets a different key. Small lists use the original renderer. The cache is bounded at 32 MB. Blank prompts, field attributes, validation and location hierarchy behavior remain outside the cache and unchanged.
- User form catalogue reads reuse their exact existing per-slug timestamp sort within one request. A fresh outer array preserves caller mutation isolation and the original equal-timestamp ordering.
- Dashboard FCO lookup indexes all original office IDs and normalized aliases once per request. Multiple IDs for one office, ambiguous aliases, explicit-ID/name collisions and original preference order are retained. Replacing/resetting the request-local source directory rebuilds the index.

The earlier working-tree fixes remain: indexed legacy training owner visibility, revision-keyed scalar dropdown reads, warm master-page hydration restricted to 15 rows, and field readers that avoid evaluating unused aliases.

## Measured components

| Synthetic actual-Rails benchmark | Before | After | Verified output |
|---|---:|---:|---|
| 8,000 location options, warm render | 59.94 ms / 128,073 allocations | 5.65 ms / 66 allocations | Identical HTML bytes, selected values and escaping |
| Same option cache, cold fill | 59.94 ms original | 57.02 ms cold | Same 549,819 output bytes; no general cold-speed guarantee |
| 1,000 FCO lookups across 100 offices | 1,292.84 ms / 8,376,059 allocations | 7.84 ms / 48,917 allocations | Identical office IDs and ordering |
| Earlier 500-record/500-owner visibility read | 1,050.30 ms | 5.97 ms | Identical selected owners |
| Earlier warm 1,000-row master page | 20.86 ms | 13.05 ms | Identical complete selected records |
| Earlier photo-heavy scalar dropdown | 6.55 ms | 1.46 ms warm; 7.16 ms cold | Identical values and ordering |

These measure components, not full HTTP requests or production latency. Location HTML caching helps large lists and warm reuse; it does not remove the first construction of the complete hierarchy map. The new JJ form normally has empty child dropdowns, so a hierarchy-build bottleneck on that page must not be represented as solved merely by caching option HTML.

## Priority-page disposition

| Priority | Page | Implemented work / remaining limit |
|---:|---|---|
| 1 | training-form-list | Indexed legacy-owner fallback, existing latest-revision query-build memoization and lightweight candidate reads. Full production latency remains unmeasured. |
| 2 | vrps/new | Early-exit location readers and exact option-HTML reuse where lists are large. Existing escaped hierarchy cache retained; cold hierarchy construction remains. |
| 3 | users/new | Early-exit field readers, reuse of source ordering, cached large dropdown HTML and existing payload cache. Cold payload construction remains. |
| 4 | dashboard | Request-local FCO ID/alias index plus shared read improvements. Remaining aggregate calculations and production GC/resource costs need measurement. |
| 5 | jj-mapped-farmers | Existing external JJ catalogue cache is retained at its original ten-minute TTL. A cold API call can still block; no timeout/freshness changes were made. |
| 6 | jeevika-jankar-bill-list | Shared FCO/field/legacy-owner reads improved where used. Financial rules remain; full bill calculation/render timing is not claimed fixed. |
| 7 | gram-panchayat-master | Warm unfiltered pages instantiate the existing 15-row page; scalar dropdown reads are revision-cached. Cold SQL/projection costs remain. |
| 8 | vrps | Earlier selected staff edit/delete lookups and shared field readers retained. No new claim that full registration-list processing is solved. |
| 9 | target_mappings | Existing scoped reads/signature-free association loading retained. No new direct optimization of the entire target entry page is claimed. |
| 10 | jeevika-jankar-payment-list | Shared office/read improvements where used; existing financial visibility and calculation regressions checked. End-to-end timing remains unmeasured. |

## Verification

- Combined final suite: **216 tests / 3,489 assertions, six failures and four errors**. All ten failing/error test names match the previously established pre-task baseline; 206 tests pass. No new failure was found in this suite.
- Additional real-login integration run: **one test / 16 assertions, zero failures/errors**. User and JJ registration pages rendered with 120 states on both cold and warm requests, with identical complete option HTML and retained hierarchy attributes.
- Total across those two runs: 217 tests, 3,505 assertions; 207 passing tests and ten known failing/error checks. This is not an all-tests-pass claim.
- Explicit parity coverage includes XSS-sensitive labels, selected/multiple/disabled values, changed options, cached-output mutation, same-timestamp source order, office alias/ID collisions and directory reset/replacement.
- Syntax and `git diff --check` pass. No JS or financial/workflow rule was changed.

The ten old checks remain unresolved: attendance, training visibility/request setup, contact fallback, FCO query-count expectations, incomplete VRP fixture, location-cache test setup and photo naming/upload expectations. Some concern test assumptions or setup rather than confirmed production defects. The full application is not certified issue-free.

## Completion and timing limits

The local code fixes and verification above are ready. A reliable estimate for eliminating the remaining production delays requires deployment and representative runtime evidence, particularly cold hierarchy build stages, full financial/report calculations and external API waits. A precise finish time or a universal 3–5 ms page target would be unsupported by the supplied logs and synthetic data. No changes were made to external cache TTLs, retry/timeout behavior, permission scopes or financial results just to reduce a timing number.
