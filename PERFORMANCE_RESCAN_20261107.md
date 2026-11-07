# Performance rescan — 7 November 2026

Latest supplied production logs cover 05:58–06:01 UTC. This report replaces the earlier rescan's final-state description. Changes remain local; no production deployment, migrations or authenticated production requests were performed.

## Findings and fixes

- VRP edit: 11,158 ms / 73 queries. User new/edit: 12,222 / 11,522 ms, with approximately 3 seconds of GC each. The user form cached a hierarchy array, copied it on every request and serialized/escaped it again in the view. It now caches the identical escaped HTML attribute and omits the unused hierarchy array from the cached form payload. Dropdown arrays remain isolated per request.
- VRP forms likewise now cache the identical escaped attribute. Their eager hierarchy build was removed: a warm form no longer rebuilds the hierarchy before rendering the cached attribute. Location label queries reuse results by source revision and exact filter arguments. Original filtering, fallback labels, sorting and selected values remain in use.
- User and VRP cache revisions now include PostgreSQL tuple identities, detecting timestamp-preserving imports, repeated updates in one transaction, deletions and savepoint rollback. Both bounded process-local caches have 64 MiB caps so the escaped catalogue and dropdowns can coexist. These are per-process caps, increased from 16 / 24 MiB; production RSS remains to be measured.
- Bill Send for Approval returned HTTP 302 after PATCH. The logs show PATCH replayed against the bill-list URL and a RoutingError. Bill send/state and module status redirects now return 303, retaining their destination, flash messages, permission checks, writes and approval history.
- Shared deletion and bill PATCH fetches previously downloaded the redirected list and then reloaded it again. They now handle redirects manually and perform one visible reload, avoiding the duplicate list render and preserving flash messages for that reload. Existing error checks and deletion concurrency are retained. The separate module JSON deletion handler is unchanged.
- Module and JJ Edit / Select All handlers now use immediate document delegation, avoiding deferred initialization waits and duplicate per-button bindings. Original selection rules, alerts and destination URLs are retained. View links continue to use their original server routes and benefit from the form rendering improvements.
- Repeated training revision queries still cost 2,478–2,952 ms in the supplied production logs. The previously prepared local snapshot-aware revision cache remains intact. These logs do not establish that the local changes have been deployed.

## Measured verification

Isolated local PostgreSQL database. Synthetic writes rolled back. No production data, browser/network or concurrency benchmark.

With 8,000 synthetic villages, three warm comparisons asserted identical HTML bytes and label arrays:

| Measured preparation step | Before, ms | After, ms |
| --- | ---: | ---: |
| VRP location HTML | 168.60–191.56 | 3.90–5.82 |
| User form data and location HTML | 76.17–108.10 | 7.80–14.59 |
| Filtered village labels | 77.62–103.18 | 6.60–12.25 |

The VRP escaped attribute was approximately 2.36 MB. User baseline recreates the original cached payload, count/MAX timestamp probe, deep copy and view escaping. The optimized path measures loading current form options and its cached escaped attribute. These are preparation steps, not entire HTTP requests.

- Focused Rails regression run: 61 tests / 331 assertions, zero failures/errors. Covers original monthly training, revision cache, hotspot and location behavior plus new escaped-byte parity, warm cache reuse, filter separation, mutation isolation, direct edits, savepoint rollback and bill redirect/history checks.
- Existing VRP integration tests: 7 tests / 54 assertions, zero failures/errors.
- Seven JavaScript files passed, covering immediate module/JJ selection and edit handlers, completed navigation, mutation redirects and HTTP errors, billing load, location options, target payload/selection and pagination.
- Local page audit: 170 requests, no exceptions or HTTP 4xx/5xx. Mostly empty application data, admin viewer, two sequential passes. User new: 11.20–14.62 ms; VRP new: 30.15–48.66 ms. These are not production-scale edit/delete/view measurements.
- An existing end-to-end approver-visibility test fails at vrp_dashboard_test.rb:1554. The same failure reproduced in the isolated unchanged original HEAD checkout. Permission/visibility business rules were not changed to silence it. The earlier expanded suite's four failures and one fixture error are also not represented as passing.
- `git diff --check` passed.

## Remaining work outside local verification

Deploy the intended source revision, compile matching assets and restart the application before measuring the live service. Verify production query plans, migrations, host RSS/GC and concurrent request behavior. Full-page edit/delete/view latency of 3–5 ms has not been established; the measured improvement at that scale applies only to warm VRP location HTML preparation.

Reproduce with a dedicated test database:

```sh
RAILS_ENV=test bundle exec rails runner script/form_location_render_performance_audit.rb
RAILS_ENV=test PERFORMANCE_AUDIT_PASSES=2 bundle exec rails runner script/performance_audit.rb
```

## Application-wide follow-up

Expanded the scan across all module pages, shared forms/lists, admin/staff/JJ roles and the read API inventory. The two final audits measured 170 admin page requests plus 320 role/API requests, including populated JJ View/Edit, user Edit and recent target-list pages. No request raised a server exception or returned HTTP 5xx. All 316 common role/API response statuses matched the pre-change audit, including existing HTTP 403/422 permission/validation responses.

Additional fixes:

- Recent target lists and JJ target lists no longer build hidden entry-form location/activity dropdowns or edit payloads. The table, visibility/filter scopes, target grouping, labels and XLSX export are retained. JJ target-list queries fell from 16 to 12; the empty admin recent-list audit uses 6 queries instead of the earlier 11. Local recent-list requests measured 6.72–7.09 ms, with mostly empty data.
- Admin JJ View now fetches the requested JJ directly, retaining its full detail attributes. It no longer materializes every JJ and the approval queue to establish visibility already granted to admins. Non-admin visibility remains unchanged. A regression verifies only the selected JJ is instantiated.
- JJ detail location labels skip catalogues when no village/GP is selected and share one request-local matching scan across state, district and block labels. Existing matching rules and village-before-GP priority are retained.
- List delete/send/status controls now initialize before deferred form/catalogue setup. Binding state uses a WeakSet of live bodies, so repeated boots do not duplicate listeners and restored/cloned bodies receive working bindings.
- Removed remaining background redirect downloads from JJ send, AFL bulk deletion and module/user status fetches. These actions retain a single visible reload, their existing mutation requests and CSRF headers. User status HTTP failures are now reported instead of being silently ignored.
- User and JJ edit/delete/status redirects, AFL deletions and target deletion use HTTP 303 where applicable so non-GET requests navigate back with GET. JSON response paths, affected records, notices and list filters are retained. The HTTP redirect status intentionally changes to fix method replay.

Final verification: 74 combined Rails tests / 404 assertions plus 2 deletion integration tests / 18 assertions passed; 10 JavaScript files passed. The tests cover single-JJ detail loading, skipped hidden form work, read-only XLSX export, location label reuse, primary-action boot/restoration, redirects and HTTP errors. `git diff --check` passed. The previously documented broader baseline failures remain unresolved and are not included in the passing totals.

The populated local role audit measured admin JJ View at 22.34 ms, JJ Edit at 26.36 ms and user Edit at 12.36 ms. These use one synthetic JJ and do not establish production latency. No application-wide maximum of 5 ms has been achieved or verified. Production deployment, matching compiled assets, live query plans and host/network/browser measurements remain necessary.
