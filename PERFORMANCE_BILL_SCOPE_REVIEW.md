# JJ bill scope and performance — 2026-10-05

The user explicitly requested this visibility change: admin sees all bills; CC sees bills belonging to mapped JJs only; agronomist and FCOC accounts see JJs in their FCOC. These staff scopes are checked before creator/approver fallbacks, so an unrelated creator/approver label cannot widen the scope. Accounts without an office do not receive an organisation-wide fallback. Other account types retain the previous visibility path.

Bill List adds FCOC Name from the JJ registration with legacy saved-field fallback. Training Form List adds FCO Name using existing saved field aliases. Existing month/status filters remain in place.

The latest log has training-form requests up to 78.686 seconds, including 56.702 seconds Views, with 28 queries / 4 cached. The former hierarchy query repetition is reduced, but rendering and DB waits remain substantial. API JJ form-options reaches 69.761 seconds with 287 queries / 265 cached. The shared API VrpAccess now caches ordered user reads and approver labels within the request.

Training HTML transport deduplicates identical farmer metadata across targets. The browser restores the original mapping and farmer arrays before existing form handlers use them. Farmer IDs, order, missing-record flags, different metadata for the same ID, selection behavior and API responses are preserved. Older array-format HTML remains supported.

A synthetic 100-target / 200-repeated-farmer payload measured 4,121,391 bytes originally and 224,186 bytes packed (94.6% smaller). This is a payload benchmark, not a production response-time measurement. The actual Ruby-packed sample was decoded using the JavaScript helper; full output equality, old-format handling and independent farmer objects passed.

Validation: 59 Rails tests, 536 assertions, zero failures/errors. JavaScript syntax and cross-language round trip passed. Existing API master tests emit nonfatal duplicate JSON key warnings. No production restart, deployment, or index migration was performed. INFO request logs do not establish PostgreSQL wait events or deployed index validity; PERFORMANCE_DIAGNOSTICS.sql remains the read-only diagnostic for that evidence.
