# Village farmer cache batching

Latest log callsites around TargetMappingsController external_village_farmers_for show repeated cache database operations for large village selections. Each village previously used a separate Rails.cache.fetch inside its worker. The cache can therefore amplify SELECT/DELETE/INSERT traffic while the page also waits on external APIs.

Changed detail-list retrieval to read_multi and write_multi per existing six-village batch. Cache keys, one-minute expiry setting, raw cached rows, selected-label decoration, nil-result rejection, empty-list reuse, final farmer-ID deduplication and sorting remain. API calls still run in executor-wrapped threads, bounded at six, and cached rows do not trigger an external call. No permission, assignment, save validation or database mutation rule was changed. Farmer-count cache logic was not edited.

Verification: 53 tests / 241 assertions passed across village fallback/cache behavior, count endpoints, ICS/village selections, target entry/list reads, monthly training reads, bill rows, latest revisions and approvals. The seven-village test observes two batch cache reads and two batch writes; a warm second request has no API calls or writes. Empty results remain reusable, raw village data remains undecorated in cache, and unavailable responses still raise without being cached. Diff check passed.

This reduces cache round trips. It does not accelerate an uncached upstream response, establish live milliseconds, or prove all supplied slow requests resolved. No production deployment or authenticated production timing was performed. Previous separately documented broad-suite failures remain outside these passing checks.
