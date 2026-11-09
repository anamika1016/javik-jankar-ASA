# Other Target forms: skip excluded payloads

Both Other Target entry paths previously materialized every visible target, including serialized farmer lists, and preloaded their JJ owners before applying activity eligibility. Other with Farmer also preloaded completion state for targets it would later discard.

The forms now reuse TargetFormReadQuery to decide activity eligibility using only target ID/main activity/subactivity headers. Only eligible targets then load their full payload and owner/completion data. Ordinary Other retains every configured non-training activity except Other with Farmer; Other with Farmer retains only its own configured type. The original final predicates and exhaustion check remain. Scope visibility and final ordering are preserved.

New before/after test compares complete mapping hashes against bypassing the early header filter for both forms, and confirms only eligible target IDs reach owner preload. No external APIs are called by that test. Related regression run: 68 tests / 519 assertions, zero failures/errors. The test fixture initially needed required owner fields and a dependency-free baseline override; those test setup problems were corrected before the passing run.

This removes unnecessary work in the logged Other Target / Other Target with Farmer render paths. It is not a production latency measurement or a claim that all request delays are resolved. No business calculations, permissions, save validation, endpoint response fields or exhaustion rules were changed. No deployment performed.

Combined follow-up review: 150 Rails tests / 1,090 assertions and ten JavaScript test files passed. Includes all current uncommitted optimizations together, exact revision-summary parity, full Other Target mapping parity, billing fallback/output parity, cache invalidation, forms, approvals and navigation regressions. Diff check passed. No additional confirmed regression or justified speed change was found during this review. These selected passing tests do not certify every application behavior or production latency.
