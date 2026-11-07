# Behavior verification of performance changes — 7 November 2026

Compared the local performance work with original Git HEAD `666660f`, inspected remaining changes, and used an isolated PostgreSQL test database. No deployment or production database changes were made.

## Issues found and corrected

The user-form and VRP catalogue caches could publish a payload under an earlier source revision if a master changed between the revision probe and the cold payload read. A rollback/older snapshot could subsequently receive options from the wrong revision. `CatalogueReadCache` now publishes a cold fill only when a fresh source-version probe still matches its key. Warm hits retain their single revision probe. User form data, VRP projection rows, escaped VRP attributes and cached location labels use this guard; cache key versions were advanced.

Reproduced the previous unconditional-fill behavior in a separate runner process, without editing application files: the three new cold-fill regressions failed. With the guard, they pass. The scenarios change source data during a fill and verify the original options/HTML return after savepoint rollback. This is a correctness fix, not a change to permission, validation, approval or calculation rules.

The memoized JJ detail location lookup now returns a fresh array, preserving the original caller-mutation behavior while retaining its request-local matching scan. Clearing one result does not change later labels.

## Original/current parity evidence

- 46 original/current bill-evidence comparisons matched, including owner subsets, farmer fallback, empty targets/farmers, month normalization, inactive/deleted records and missing-key behavior. Ordered unapproved revision IDs also matched the original latest-revision rule.
- Eight complete user-option payload comparisons matched original Git code after expressing its hierarchy through the identical escaped HTML attribute. Covers cold/warm reads, active/lowercase/inactive status examples, all form-option master slugs, direct edits preserving timestamps and markup-sensitive labels.
- 79 focused Rails tests / 431 assertions passed. Includes monthly training reads, cache rollback/invalidation, literal revision IDs/statuses, location/HTML parity, detail lookups, read-only lists and export, redirects, deletions, notices and filters.
- Ten relevant JavaScript files passed, including primary-action startup/restoration, edit selection, deletion/status HTTP errors, CSRF headers, redirect handling, target payloads and pagination.
- 320 role/API requests had no exceptions or HTTP 5xx; all response statuses matched the prior audit, including permission/validation responses. Status parity alone is not proof of complete payload equivalence.
- `git diff --check` passed.

## Speed retained

With 8,000 rolled-back synthetic villages, three local warm comparisons asserted equal HTML/labels:

| Preparation step | Original-style read, ms | Optimized read, ms |
| --- | ---: | ---: |
| VRP location HTML | 179.44–206.24 | 3.78–4.53 |
| User form options and location HTML | 82.72–116.62 | 8.87–14.96 |
| Filtered location labels | 81.16–115.89 | 6.72–17.29 |

Warm reads still used one version query. Cold fills intentionally spend an additional version query to protect correctness. These are local preparation timings, not full-page or production latency guarantees.

## Behavior differences that must not be called identical

The existing duplicate-target picker in layout.js is a non-performance change already present before these performance rescans: when several targets match the same selects, it offers a choice instead of always selecting the first match. It and its regression tests were left intact; it was not silently reverted as part of performance work. Single-match selection is unchanged.

HTTP 303 redirects intentionally replace 302 after certain mutations to prevent PATCH/DELETE replay. Failed user-status requests now display an error instead of being ignored; successful mutation redirects avoid redundant background list downloads. These are deliberate transport/error-handling corrections, not changes to affected records or business permissions.

The previously documented approver-visibility failure and other broader baseline test failures remain unresolved. They were reproduced on original code in earlier checks and are not included in the passing totals. Universal behavior equivalence and a 5 ms application-wide maximum have not been established. Changes remain local.

## Final live-behavior follow-up

A real two-connection regression exposed one further cold-fill issue: Rails' request-local SQL query cache could reuse the initial version probe even after another connection committed a source update. The final source-version check now runs inside `ActiveRecord::Base.uncached(dirties: false)`, so it reaches PostgreSQL. This affects cold fills only; warm hits return before this check. No permissions, validation, count calculations, approval transitions or existing target-selection choices were changed in this follow-up.

The new regression failed before the correction (a new payload was cached under the old version), then passed after it. It uses a committed synthetic row, an actual second database connection, an enabled SQL query cache and explicit cleanup. No production database was accessed.

Final checks: 80 Rails tests / 434 assertions passed; 10 JavaScript files passed. All 320 role/API response statuses matched the prior audit, with no server exceptions or HTTP 5xx. Existing documented non-performance differences and broader baseline failures remain as described above; these passing focused checks do not establish universal equivalence. `git diff --check` passed. No deployment or live application changes were performed.
