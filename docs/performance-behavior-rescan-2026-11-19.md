# Performance behavior rescan — 19 November 2026

Reviewed the pending performance patch against current committed HEAD `94a30cb`, including catalogue memory storage, cache namespaces, Puma prewarming, village detail matching/hydration and training predicate ordering. No additional application-code defect was found in this pass. Application code was left unchanged; one regression test was added.

## Fresh verification

* Focused tests, including the new test: **255 tests, 1,845 assertions; zero failures/errors** (`tmp/nov19_focused_rescan.log`).
* Full suite before the additional test: **981 tests, 8,581 assertions; 23 failures, 9 errors** (`tmp/nov19_full_rescan.log`). All 32 failure/error identities match the preceding full audit; no new identities. This remains a failing full suite, not an all-green result.
* **46/46** synthetic HTTP renders returned 200. Compared these renders to the committed ModulesController and module view using the existing baseline mode: status, visible content hashes, controls, browser data and export hashes/row counts match on every request (`tmp/nov19_render_baseline.json`, `tmp/nov19_render_rescan.json`). This is fixture coverage, not proof for every possible production input.
* Role audit: **329 requests**, with 308 HTTP 200, nine 401, nine 403, two 302 and one 422; no HTTP 5xx (`tmp/nov19_role_rescan.json`).
* New regression exercises the actual immutable-cache path for the village detail index. It verifies that nested cached entries are frozen, complete selected detail data remains mutable and request-local, direct edits invalidate old aliases, updated aliases resolve immediately and direct deletion removes cached matches. Focused tests were rerun after adding it.

## Scope and performance limits

The patch changes read preparation and caching; it does not introduce new payment calculations, save rules, role rules or UI controls. Existing revision guards and full selected-row hydration remain. The cache lifecycle checks specifically guard against performance improvements accidentally serving stale edit/delete results.

No new production journal was supplied in this turn. The existing November 17 stage measurements remain local measurements; this rescan does not establish new production latency. In particular, recurring Bill List processing and external-service delays are not declared fixed. No blanket guarantee of 5–15ms page opening is supported. Deployment and production verification steps remain in `production-cpu-followup-2026-11-17.md`.
