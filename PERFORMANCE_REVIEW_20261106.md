# Performance verification — 6 November 2026

Changes are local and have not been deployed to jj.asaindia.org. No production database or authenticated production page was accessed.

## Findings from supplied production logs

- Login POST: 19ms; subsequent dashboard: 4.53–11.54s. Authentication itself is not the measured bottleneck.
- JJ Payment List: 44.988s, including 31.163s of ActiveRecord time.
- JJ Bill List: 51.696s, including 36.455s reported view time. The supplied summary understated this route.
- Many slow requests overlap; GC and request contention need verification on the production host.

## Changes

- Login uses a small entry module and the original shared password toggle instead of downloading/parsing the 367,558-byte layout module. Normal application and report entry modules are no longer preloaded indiscriminately. Agreement and password-reset pages keep their existing application entry.
- Bill training evidence reuses monthly candidates per request across JJ owners. Owner matching and farmer fallback remain independent, and blocked revisions are excluded before instantiation. Photos/documents are omitted from evidence-summary reads. Empty targets/farmer sets avoid training scans.
- Unapproved revision IDs are cached in a bounded process-local store. Each read checks a database tuple-version digest without parsing large revision snapshots. Insert, delete, timestamp-preserving edits, and multiple updates in one transaction invalidate the cache. Cold results and their version are read in the same SQL snapshot to avoid poisoning older snapshot keys during concurrent writes. Latest-ID precedence and exact Approved matching remain unchanged.
- Completed navigation clears the blue progress indicator on render and load; a cached preview keeps its pending indicator. This does not cancel background requests.

## Measured verification

Local test database, admin viewer, three sequential passes. These mostly empty module lists do not represent production row counts, network rendering, user roles or concurrency. 254 requests completed without exceptions or HTTP 4xx/5xx; some routes deliberately redirected.

| Route | Local measured range, ms |
| --- | ---: |
| `/login` | 50.86–50.86 |
| `/dashboard` | 21.22–44.91 |
| `/modules/training-form-list` | 6.41–7.05 |
| `/modules/other-target` | 11.54–14.80 |
| `/modules/other-target-with-farmer` | 11.61–19.38 |
| `/modules/jeevika-jankar-payment-list` | 7.36–8.03 |
| `/modules/jeevika-jankar-bill-list` | 6.32–10.21 |

Local login POST: 4.08ms. Public anonymous GET / measured separately: HTTP 200, first byte 350ms and total 351ms including TLS; this was the existing production deployment, before these changes.

Approval benchmark: 500 synthetic revisions with approximately 64KB random snapshot JSON each; five comparisons with Rails SQL cache disabled, exact ordered ID parity asserted. Original reads: 21.12–39.35ms; warm optimized reads: 1.34–2.75ms. Cold optimized read: 38.02ms. The cold path has version-check overhead; frequently changing revision data will reduce the cache benefit. All benchmark writes were rolled back.

Tests: 45 focused Rails tests / 242 assertions passed; 6 login/agreement tests / 56 assertions passed. Navigation/password, bill loading, target payload and pagination JavaScript suites passed.

## Remaining validation

- Initial broader baseline had unrelated contact fallback and FCO query-count failures and a VRP fixture missing required aadhar_no. Two OTP tests also cannot run with the current Minitest 6 bundle because Minitest::Mock is unavailable; the existing language-switch test mock lacks document.getElementById. These have not been represented as passing.
- The repository already contains training/month/latest-revision indexes and prior location serialization optimizations. Production migration status and query plans are unverified; adding duplicate indexes without examining live plans would not establish a fix.
- No promise is made of millisecond latency for every production situation. Deployment, authenticated production measurements, EXPLAIN (ANALYZE, BUFFERS), database statistics, host memory and concurrent-load verification remain necessary.

Reproduce:

```sh
RAILS_ENV=test bundle exec rails runner script/training_revision_performance_audit.rb
RAILS_ENV=test PERFORMANCE_AUDIT_PASSES=3 bundle exec rails runner script/performance_audit.rb
```

## Behavior rescan

- Restored an exact edge-case contract: with no targets or no assigned farmers, the training evidence index now returns an auto-initializing hash, just like original HEAD. Looking up an absent key returns `[]` instead of the `nil` introduced by the new early return. Added regression checks for both cases.
- Found stale local precompiled assets that omitted `login` and `password_toggles` from the resolved import map. Rebuilt test assets and added assertions that both imports resolve. Deployment must compile assets with the deployed source (`RAILS_ENV=production bundle exec rails assets:precompile`) before restart; old manifests must not be reused.
- Compared original HEAD methods directly with optimized methods in one rolled-back test transaction: 46 comparisons covering owner subsets, shared farmers, no farmers, no targets, mixed/blank months, soft-deleted/inactive records, duplicate attendance IDs, latest-revision precedence and exact case-sensitive statuses. Ordered evidence and missing-key behavior matched; blocked revision IDs matched exactly.
- Broader focused run: 106 tests, 755 assertions, zero failures/errors. After adding a savepoint rollback cache check, the approval/login/hotspot subset passed 35 tests and 210 assertions. Original password-toggle function text matches the extracted shared function exactly.
- An additional 25-test group reports five failures and two errors. The exact same failures/errors reproduce on an isolated unmodified original HEAD checkout: training attendance count, Cluster Incharge bill visibility, training CC visibility, photo field naming/upload validation, and two request-less controller fixtures. These are pre-existing failing checks, not proof that all original application behavior is correct; no permission/count/upload business rules were changed to silence them.
- The language-switch JavaScript test also fails on original HEAD. Its production function is unchanged in this performance patch. OTP mock-dependent tests remain excluded due to the previously documented missing mock package.
- Separate concurrent edits appeared in `layout.js` plus `seed_target_picker_test.cjs` during the rescan: they add a choice between duplicate seed/other-target mappings instead of always selecting the first. Those alter selection behavior and are outside this performance patch; they were left intact rather than reverting another in-progress edit.

These checks establish parity for the tested paths and identify known remaining failures. They do not establish universal production correctness or a latency SLA.
