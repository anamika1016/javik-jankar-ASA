# Application performance and ASA payment SMS review

## Scope and behavior

Scanned application controllers, models, services, jobs, helpers, views and JavaScript for database reads in loops, materialized lists, external HTTP calls and pagination; reviewed the major dashboard, registration, target, billing and payment paths, runtime configuration and recent staged optimizations. This is a source review and local regression check, not a production load test or proof that every application path is fast.

The staged performance follow-up changes batch agreement village resolution and reuse registration catalogues inside a request. Original output ordering, active filtering, alias precedence and missing-record fallback are covered by parity tests. Payment calculation, approval, access rules and persistence are not modified by this round's SMS change.

Separate edits appeared in the working copy during review: `modules_controller.rb` adds `in_target` to training-farmer data, and `layout.js` displays Target / Other village farmer badges. These change response/UI presentation and are not performance-only changes. They were preserved without modification by this review.

## Requested SMS replacement

`PaymentAdviceSmsSender` now uses header **ACTFSA**, DLT template **1777179179837744556**, the existing ASA account credential default, and the exact supplied message ending **Action for social advancement(ASA)**. The template application reference `11-1PJQ9MV52HOF9` is not the payment transaction reference; the actual saved transaction ID still supplies the message's NEFT reference.

Only this service's credential default, sender, template ID and message wording changed. Its sole application caller is Payment List Detail's `send_jeevika_payment_advice_sms`. Payment detail saving, selected bills, individual amounts, recipient lookup, date formatting, error handling and SMS summary remain unchanged. Gateway rejection continues to return a failed SMS result after payment persistence.

Existing `SMS_PAYMENT_AUTH_KEY` overrides the default if present. Production must use an ASA account key there if that override is configured; do not post credentials in diagnostic output. Mocked gateway tests establish request formatting and accepted/rejected handling, not handset delivery. The initial review did not send a real SMS; the later explicitly requested live test is recorded below.

## Remaining performance findings

| Path | Source evidence | Implication |
| --- | --- | --- |
| VRP list and generic module lists | `VrpsController#index` materializes visible VRPs; `ModulesController#module_records` loads module rows before Ruby visibility/sorting | Browser pagination does not bound database/Ruby allocation. Replacing this requires preserving visibility, sorting, search, full export and selection behavior. |
| Target mapping list | `TargetMappingsController#index` eager-loads VRP/mapping associations, then builds all visible row hashes | Association N+1 is addressed here; total row volume can still affect rendering and GC. |
| Farmer list | `AflsController#index` selects list columns and applies database offset/limit, with full filtered exports separate | Already uses server pagination; do not truncate exports as a performance shortcut. |
| Payment API | `Api::V1::JeevikaJankarPaymentsController#bill_records` loads complete bills; several actions map summaries per record | The API needs production query/response-size measurements. Detail fields cannot simply be removed or pagination made mandatory without changing its contract. |
| Dashboard cache | `DashboardSqlCache#revision` queries counts and maximum timestamps on four source tables | Timestamp indexes help MAX; COUNT remains a possible cold/request revision cost. Actual deployed indexes and PostgreSQL plans must be checked. |
| Targets/forms/approval labels | `TargetMappingsController` and `ApplicationHelper#resolve_external_farmer_labels_for_approval` make synchronous external farmer HTTP calls | External latency and repeated pages can hold the request. Existing timeouts are bounded per call, but totals can grow across villages/pages. No fabricated local fallback or stale cache introduced. |
| Registration masters | `VrpsController#set_master_options` invokes `sync_existing_vrp_master_records` before building options | Existing master synchronization is retained; moving/removing it could change behavior and needs separate evidence. |
| Payment-detail submission | `ModulesController#send_jeevika_payment_advice_sms` calls the gateway serially per selected bill | Gateway waits can slow the POST. Moving SMS to a background job changes immediate sent/failed summary semantics, so it was not done in this review. |
| Images and archives | Latest journal's disk responses were approximately 1 ms; bill archives read complete attachments | Server timings do not establish browser transfer/decode latency or archive memory usage. Need browser/network measurements for those paths. |

Puma defaults to three threads; the local database pool defaults to five. That default alone does not prove pool starvation. Actual deployed worker/thread/pool settings and PostgreSQL wait events are still required before tuning concurrency.

## Startup and deployment limits

Ruby syntax checks passed for **196 files** across application, configuration and migrations. Rails `zeitwerk:check` passed using the isolated test configuration, including the payment service's ASA credential constant dependency. This does not validate production secrets, SMS environment overrides, PostgreSQL access or multi-database configuration.

The supplied production configuration uses `javik_jankar_asa_production` plus separate cable/cache/queue databases, while this checkout's `database.yml` uses a different single-database layout. Preserve the actual deployment's database configuration; do not replace it with this checkout's file. No server restart, database migration, deployment or production configuration change was performed.

`PERFORMANCE_DIAGNOSTICS.sql` reads statistics inside `BEGIN READ ONLY` and sets a five-second statement timeout. It does not write application data, restart services or build indexes. Earlier index migrations use concurrent, non-unique index additions; they still consume database resources and must be verified on production rather than assumed applied. This round adds no migrations.

Use the pending production capture while a request is slow:

```bash
sudo -u postgres psql -X -d javik_jankar_asa_production \
  -v ON_ERROR_STOP=1 < PERFORMANCE_DIAGNOSTICS.sql | tee performance_output.txt
```

## Validation

- Focused SMS/performance run: **13 tests, 63 assertions, zero failures/errors**. Covers the exact approved sample, sender/template, accepted/rejected gateway responses, incomplete details, amount formatting, agreement parity and registration query reuse. Gateway responses are simulated.
- JavaScript suite: **9 of 10 files pass**; the unchanged language-switch test fails because its document mock lacks `getElementById`, matching the earlier baseline. Pagination, bill-loading and target tests pass.
- Full application regression run: **342 tests, 2,205 assertions, 19 failures and 6 errors**. Compared against the unchanged committed baseline (332 tests, 2,163 assertions): all 25 failure/error test names are identical, with no introduced failures. The application test suite is not fully green.
- `git diff --check` passed. Local startup checks passed; production startup and real SMS delivery remain unverified.

## Follow-up: explicit single live SMS test

On 12 October 2026, sent one explicitly requested test to the mobile number ending **9227** through the configured gateway using **ACTFSA / 1777179179837744556**. Reference **TEST-ASA-SMS**, amount **0**, beneficiary **SMS TEST - NO ACTUAL PAYMENT**. No payment row was created or modified.

Gateway returned HTTP **200**, success **true**, and **SMS submission has been accepted successfully.** This confirms gateway submission acceptance; handset receipt or a delivery report has not been observed. No automatic retry or second message was sent.

Rechecked the entire current tracked diff against HEAD, including staged and unstaged Ruby/JavaScript. The registration/agreement optimizations preserve tested output semantics; optional tracing is disabled by default. The separate training badge and `in_target` response changes remain presentation changes, so the workspace cannot accurately be described as having no JavaScript or output changes. Selection, payment persistence and approval code are unchanged in these diffs.
