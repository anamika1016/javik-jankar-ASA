# Training-list revision query

The supplied log identifies a 5,080 ms query at the training-list revision-summary load. For a nonempty selected training-ID set, latest summaries now use one indexed LATERAL top-row lookup per exact record reference instead of DISTINCT ON over matching historical revisions. Highest revision ID still wins; summary projection, controller ordering and automatic approver assignment remain unchanged. Nil/empty top-level scopes retain the previous global lookup behavior. Exact string references such as `12` and `012` stay distinct; absent references return no row.

The existing partial index `index_training_edits_on_record_id_and_latest_id` supports the targeted lookup. It must exist in production; no production migration or deployment was performed here.

Validation: 76 tests / 540 assertions passed, including new full-summary parity comparisons with duplicate references, missing IDs, nil members, leading zeros and unrelated module records. Training read scaling, approvals, bill-row parity, dashboard reports and log hotspot tests passed. Diff check passed.

Isolated PostgreSQL benchmark: 2,000 synthetic revisions, 10 requested record references, five uncached reads per approach. Median previous query 2.87 ms; targeted query 0.49 ms. Full summary values matched. Data creation was rolled back. This benchmark is not production-sized evidence and does not establish that the logged 5-second delay is fully resolved.

Other multi-second requests with little SQL/view time still require production runtime profiling. GC remains enabled. No claim that all pages are fixed is made.

## Follow-up experiment

Tested caching decoded VRP location rows to avoid JSON parsing on warm form requests. It passed 59 tests / 319 assertions with related form/training/billing paths, but a 1,000-row MemoryStore microbenchmark was slower (median 2.87 ms versus the existing 2.58 ms). Reverted that experiment and its temporary test; neither is retained. This result illustrates why reducing an individual operation is not by itself evidence of faster pages. The existing VRP form implementation is unchanged by this review.
