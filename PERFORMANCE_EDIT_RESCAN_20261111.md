# Edit/view rendering rescan — 11 November 2026

The latest attachment repeats the historical slow-request list; it does not contain fresh post-deploy production measurements. **Not all listed issues are resolved.** This pass fixes an additional cause of the worst edit-page rendering and verifies the changes locally. Earlier log coverage and every completed request are in `PERFORMANCE_LOG_REVIEW_20261111.md`.

## New fixes

1. **Location master edit pages now paginate their Saved Records table.** Previously State/District/Block/GP/Village lists were paginated only when no record was being edited. Opening a village edit therefore loaded/rendered every village again. Edit pages now use the same 15-row sorted page and revision cache as the list. The selected record/form remains complete even when it is outside that saved-record page.
2. **Table paging/search uses a separate Turbo frame.** The edit form is outside that frame, so its unsaved browser values remain in place. Paging/search URLs retain the selected record's edit path. Frame requests render only the table partial, skipping the edit form, layout and large location catalogue. Record Edit/Delete/Status and import/export actions retain full navigation through the frame's `_top` target. Non-master tables retain their existing rendering/navigation.
3. **GP dropdowns project only eight relevant alias fields.** The old special-case reader instantiated complete GP ModuleRecords, including unrelated uploads. The replacement preserves first-non-code precedence, text trimming, JSON type conversion, inactive filtering, creation order and unique labels. Revision-checked caching reuses the result and detects direct updates; callers receive independent copies.

The previous pass's LG/Office unused-list removal, admin-only visibility bypass and Set-based LG bulk matching remain included.

## Complete edit-response benchmark

`script/benchmark_master_edit.rb`, baseline HEAD `6e1407e63f00e7c606630f1dc68d8661c7132943`, isolated local test database, 15,136 synthetic village rows, all writes rolled back. Complete edit-form inputs/selects/options/textarea markup is compared after omitting randomized authenticity tokens. All form fields/options matched.

| Request | Before ms | After ms | Response bytes before → after | Saved rows before → after |
|---|---:|---:|---:|---:|
| Cold edit | 2,628.48 | 1,711.73 | 21,309,068 → 7,091,081 | 15,136 → 15 |
| Page 2 frame request | 1,883.69 | 208.58 | 21,295,646 → 16,292 | 15,136 → 15 |

Cold edit allocations: 4,412,927 → 3,316,380. Page 2 allocations: 3,275,930 → 353,549. These are single synthetic in-process HTTP measurements, excluding internet transfer and browser parsing. They do not predict production latency. The cold response is still large and is not instant; the complete location dropdown catalogue is retained.

## Verification

- Combined Rails suite: **127 tests, 2,059 assertions, zero failures/errors/skips**. Includes edit frame responses, saved-page counts, selected record preservation, search/links, alias/type parity, cache invalidation, existing master scaling, training ordering/routing, staff scope, billing scaling and farmer rendering.
- Three existing JavaScript test files pass: location options, table pagination performance and navigation completion.
- Ruby syntax and `git diff --check` pass.
- A complete browser test of typing unsaved edits then paging was not run. Integration tests verify that the form is outside the table frame, frame requests contain no form/location payload, navigation targets are correct and the returned table preserves row actions.
- No migration/business-write algorithm changed; no deployment, production restart or live timing verification was performed.

## Status of the supplied priorities

| Historical issue | Current status |
|---|---|
| Village edit — 18.267 seconds | Additional root cause fixed: edit-only full-table rendering. Full form remains large; production improvement unmeasured. |
| LG Directory — 12.049 seconds | Unused duplicate list removed and bulk matching improved in prior pass; cold build/all-row directory rendering still costs time. |
| Block Master — 8.467 seconds | Existing list pagination/caches retained; edit pagination and GP dropdown improvements now apply. Cold hierarchy cost remains. |
| User new/edit — 7.293/7.515 seconds | Existing form-option and escaped-catalogue caches retained and tested; no additional user-form fix in this pass. |
| JJ catalogue — 7.539 seconds | External upstream wait remains; not solved by these Ruby rendering changes. |
| Village list — 5.106 seconds | Existing 15-row warm-page cache retained; complete cold sort/catalogue cost remains. |
| Bill list — 4.717 seconds | Billing regression tests pass; no new bill-specific performance fix in this pass. |
| LG bulk redirect — 4.247 seconds | Set matching/empty-selection fast path included; status/write behavior retained. |
| Target mapping — 5.403 seconds | No additional fix in this pass; earlier payload optimizations retained. |
| Staff training visibility — 3.874 seconds | Remains; admin bypass does not apply to the logged staff request. |
| JJ index/approvals — 3–4 seconds | No additional fix in this pass. |
| Office API — 3.314 seconds | Unused local list removed; external wait remains. |
| Bill process edit — 3.291 seconds | Existing behavior covered by billing tests; no new specific fix. |
| Activity/training dropdown SQL — up to 2.536 seconds | GP projection improved; other cold scalar queries still need production query plans. |
| Payment list/detail and dashboard | No new specific fix; existing tests/optimizations retained. |

Fresh production request logs after deploying these changes, and production-sized query plans/browser traces for remaining hotspots, are needed to establish which bottlenecks dominate next. No claim that all pages are resolved or under 5 ms is supported.
