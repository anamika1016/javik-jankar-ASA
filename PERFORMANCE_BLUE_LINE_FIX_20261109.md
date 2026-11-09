# Completed-page progress indicator and bill-list rescan — 9 November 2026

Reviewed the supplied 7 November logs and screenshot. Changes and verification are local; no production deployment was performed.

## Progress fix

The previous handler removed `.turbo-progress-bar` elements on render/load but did not cancel Turbo's delayed visit/form indicator timers or reconcile its internal progress state. A late timer could show the indicator again.

Added a small `navigation_progress` entry dependency before layout initialization. On a final page render/load it calls the installed Turbo adapter's indicator cleanup methods and removes existing bars. A completed-page CSS flag also hides any late orphaned bar. New visits/submissions remove the flag so actual loading remains visible. Cached previews retain the pending indicator. Stream/validation submission completion clears progress when no follow-up page visit is pending. Native page restoration is covered by `pageshow`.

This code stops indicator timers, not navigation, requests or submissions. It does not use `window.stop`, abort requests, disable Turbo or change permission/workflow rules. The old layout-only DOM-removal handler was removed.

## Bill-list improvement

Bill rows previously calculated totals for every record before applying the displayed month/state filters. The month picker now reads the same month values from all records, while the existing month/state predicates select calculation candidates first. Workflow-status filtering remains based on the existing calculated label. Unfiltered admin views retain all records. Original order, labels, amounts, targets and achievements matched in 15 combinations covering blank/legacy months, exact case-insensitive matching and active/inactive states.

This avoids work for filtered-out historical bills; it does not establish that every 40-second bill calculation is fixed.

## Verification

- Real isolated headless Chrome, using the installed Turbo 8.0.23 implementation: pending bar, cached preview, final render, delayed timer cancellation, late orphan suppression and next-navigation indicator all passed. The browser test uses a short test-only progress delay; production Turbo delay was unchanged.
- 93 focused Rails tests passed, including billing/report/approval regressions and complete filtered-row parity. The final compiled JS/CSS asset-serving integration check also passed.
- Ten JavaScript test files passed, including submit completion while a redirect visit remains pending.
- 320 role/API requests: no exceptions or HTTP 5xx; all response statuses matched the prior audit. Existing permission/validation responses were retained.
- Test assets compiled successfully; the new import map pin resolves to a served compiled module. `git diff --check` passed.

## Supplied logs and remaining limits

The newer log contains bill-list responses of approximately 37–45.5 seconds, payment-list requests around 13.5–15.4 seconds and dashboard requests up to 36.9 seconds. Earlier supplied bill-list logs report roughly 42–43 seconds of view time. Repeated small SQL/schema reads also take approximately 800 ms during contention. Production CPU/RSS/swap, database waits and representative data profiles remain unverified. Two login CSRF failures are also present; their cause is not established, and CSRF protections were retained.

The progress fix does not turn those backend durations into millisecond responses. No application-wide maximum latency or authenticated production timing is claimed. Existing documented broader baseline failures remain outside the passing focused results.

Deployment must compile matching production assets before restart:

```sh
RAILS_ENV=production bundle exec rails assets:precompile
```

This is required for the new module, import map and CSS to reach users. The command was not run against production by this rescan.

## Final regression rescan

Found and corrected one additional navigation edge: a late initial `DOMContentLoaded` or older `turbo:load` event could hide the indicator for a newer active visit. Those completion events now clear progress only when no initialized/started visit exists. Actual final renders still clear immediately, and persisted browser back/forward restores clear stale state. The regression failed before the guard and passes after it. No requests or submissions are cancelled.

Added populated billing parity checks with two actual JJs, October/November targets, training records, active/inactive bills and live calculated totals. Complete row hashes—including amounts, targets, achievements and original ordering—match calculating all rows first and then filtering, for nine additional filter combinations. The existing 15 legacy/blank filter combinations also pass.

Final combined run: 139 Rails tests / 957 assertions, zero failures/errors; ten JavaScript files passed. Isolated Chrome with the real Turbo 8.0.23 implementation passed the updated lifecycle check. Assets were rebuilt and the compiled module/CSS serving test passed. `git diff --check` passed. Previously documented broader baseline failures and production latency limits remain; this is not a claim that the entire application is issue-free. No production deployment was performed.
