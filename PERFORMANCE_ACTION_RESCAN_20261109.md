# Action and training-list rescan — 9 November 2026

Changes are local; production has not been deployed or timed.

Latest audit: **200 tests / 2,221 assertions; 190 passing tests, six failures and four errors**. All ten remaining failing/error checks also reproduce with the original controller methods. No new production-code change was made during this fourth review. Details and limits are recorded below.

## Confirmed bottleneck

`training_edit_revision_for` built the complete latest-revision SQL before checking its request-local result cache. Each training-list sort key and button lookup quoted and joined all candidate IDs again. For N candidate records this caused quadratic Ruby work even though SQL query counts stayed low. The supplied log's training-list request took 20,365 ms with only 103.8 ms of Active Record time; the log alone cannot establish how much this particular bug contributed.

Query construction now happens inside the existing memoized fill. Revision selection, latest-ID precedence, pending-first ordering, automatic approver assignment and request snapshot behavior remain in place.

Staff JJ edit/update/delete lookups now fetch an owned record by ID, then check the requested ID within the existing fuzzy cluster-label scope. They no longer materialize all owned/mapped JJ records and signatures. Own-or-mapped authorization and complete selected-record attributes are retained. Bulk/list visibility is unchanged.

The initial dashboard FCO DISTINCT optimization was removed during the follow-up behavior audit. For legacy aliases absent from the office directory, DISTINCT can reorder values and change the first displayed label. The original query and label behavior are restored and covered by a dashboard integration regression.

Training edit now supplies only its selected training ID to the existing indexed latest-revision reader. Approved, Rejected and Pending summaries, exact reference matching and latest-ID precedence are tested. A rollback-only benchmark with 500 unrelated revisions reduced instantiated rows from 502 to two and action time from 10.50 ms to 1.68 ms with identical revision output; authorization and rendering are stubbed in this benchmark, so these are not HTTP timings.

## Verification

- Actual Rails helper/query-builder comparison using 1,000 candidate IDs and three lookup passes against the isolated local test database: 4,640.40 ms / 15,264,012 allocated objects before; 5.05 ms / 11,237 allocated objects after. Returned outputs matched. This is a helper microbenchmark with synthetic candidate IDs, not an HTTP or production latency measurement.
- New regression checks ensure 600 training row/button lookups build the candidate query once, including cached missing revisions. Staff lookup checks retain owned/mapped access, deny unrelated/missing IDs, return complete attributes and instantiate only the two requested authorized rows despite signature-heavy mapped siblings.
- Focused suite: 84 tests / 1,565 assertions, zero failures/errors. Covers revision reads, monthly training, JJ forms/controller, training approvals, dashboard, lookup scaling, cluster scope and training-owner indexing.
- A broader 83-test run exposed two failures and two errors in existing training attendance/visibility tests. All four reproduce with the original revision helper: grouped attendance expects 10 but receives 2; similar-name CC visibility fails; two controller-less visibility tests call `filtered_parameters` on a nil request. These are unresolved baseline issues; this rescan does not claim the entire suite passes.
- Ruby syntax checks and `git diff --check` passed.

Follow-up final verification: 136 focused tests / 1,888 assertions, zero failures/errors. Broader checks exposed eight distinct existing failures/errors in four test files; all eight reproduced after restoring all modified controller methods from Git in memory. These unresolved baseline issues include the four earlier failures plus saved contact fallback, FCO query-count expectations, an incomplete VRP fixture and controller-less location request setup. See `PERFORMANCE_LOG_REQUEST_AUDIT_20261109.md` for all 91 captured requests and all 16 slow SQL entries.

## Third behavior and lookup review

Single-JJ staff actions now restrict the cluster-label DISTINCT query to the requested ID as well as restricting the final record query. The original fuzzy matcher, own-or-mapped permission, list scope and selected record attributes remain unchanged. This avoids scanning unrelated cluster labels even when a staff user has few mapped records.

New parity coverage compares the optimized lookup with the original own-plus-full-mapped-list selection across blank labels, case/spacing, role suffixes, fuzzy matches, different current-user labels, owned/unowned records and missing IDs. A SQL regression verifies both targeted queries contain the requested ID filter.

Latest focused run: **140 tests / 1,972 assertions, zero failures/errors**, including user/farmer deletion redirects in addition to earlier checks. Syntax and diff checks pass. The eight previously confirmed baseline issues remain unresolved; this is not an application-wide all-tests-pass claim.

Rollback-only actual-Rails staff lookup benchmark with 500 unrelated labels: **17.04 ms / 501 label comparisons before; 2.84 ms / one comparison after**. The complete returned record matched. This uses synthetic records, stubbed current-user identity and an empty own-record scope; it measures the lookup, not full authenticated HTTP latency. No production deployment or latency guarantee is claimed.

## Fourth expanded audit

Added an authenticated HTTP training-edit regression with real login, routing and rendering. It verifies latest-ID precedence despite older timestamps, preserved original/proposed snapshots, unchanged live training data, automatic Agronomist assignment, no new revision creation and stable second-page-open behavior. It passes with both optimized and original controller methods.

The full page's existing sidebar also automatically routes other visible pending requests. This behavior existed before these optimizations and remains unchanged. The selected-record read optimization does not mean that the complete page never reads or updates other revision routing metadata. Earlier action microbenchmarks stub rendering and therefore exclude this sidebar cost.

The expanded run completed 200 tests / 2,221 assertions with six failures and four errors. The original-method comparison completed 37 relevant tests with exactly the same ten failing/error test names. Remaining checks are:

| Area | Remaining checks | Finding |
|---|---:|---|
| Grouped attendance | 1 | Expected total 10, rendered total 2. |
| Training visibility | 3 | Similar-name expectation mismatch; two controller-less tests fail on absent request state. |
| Saved contact fallback | 1 | Expected saved fallback text, received nil. |
| FCO aggregate performance | 1 | Expected one counted SQL query, received three. |
| API dashboard fixture | 1 | Test inserts an incomplete VRP violating the database aadhar constraint. |
| Location cache test setup | 1 | Missing compatible request/params state in a controller-less test. |
| Photo naming/validation | 2 | Close-up field key expectation differs from parameterization; non-image MIME with a `.png` filename is accepted by the existing extension fallback despite the test expecting rejection. |

These are unresolved checks, not ten proven production defects. Some concern test setup or expectations; deciding intended photo acceptance/name matching rules would change behavior and is outside this behavior-preserving optimization. No upload policy, attendance calculation or visibility rule was silently changed to make these tests pass. Syntax and diff checks pass; no new regression was found in the examined paths. This is not proof that every application path is issue-free.

The full application cannot be claimed to respond in 3–5 ms. Production CPU, memory/GC, database waits, payload sizes and end-to-end action timings still need measurement after deployment. This patch removes confirmed avoidable work without changing workflow rules to meet an unverified latency target.
