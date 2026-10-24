# Listed slow pages and all GET API routes — 24 October 2026

Further code changes are local and have not been deployed. This audit uses an isolated PostgreSQL test database, not production. It extends the earlier incident and application scan reports.

## Additional bottlenecks fixed

1. The mapped-villages and mapping-only drill-downs computed every target's achievements and farmer status sets before rendering lists that never used them. These branches now skip that work and the unused bill read. Selected-target farmer lists still execute their own existing selected-target calculation. Assigned, achieved and pending target branches retain progress calculations.
2. Achievement/completed-farmer reads downloaded complete Other Target activity JSON, including fields not used by the calculations. A read-only projection retains matching fields, approval/deletion flags, selected farmers, achievements and dates; it omits unrelated image/metadata payloads. Tests compare calculated achievements and farmer IDs to full-record reads, preserve JSON value types and verify stored data is unchanged. One synthetic record projects to less than 1% of its full JSON size.
3. Web JJ dashboard target loads and the JJ dashboard API now preload JJ associations without signature images. The API's admin JJ catalogue and dashboard-specific JJ lookup use the same explicit read scope. Authentication itself retains its existing active/deleted checks; no global default projection was introduced. Signature storage and agreement reads are unchanged.

The earlier improvements remain: revision-checked shared location catalogue, signature-free session/target selector reads and owner/month indexing for achievement matching. Existing totals, filters and authorization predicates remain in place.

## Verification coverage

- All 18 API test files executed: **150 tests, 700 assertions, three failures, zero errors**. All three failures are in the existing sidebar test file and reproduce with the original HEAD controllers: two legacy menu-label expectations and a blank-can-view access expectation. The suite is not fully green. Those access rules were not changed to satisfy the tests.
- Focused dashboard, target, cache, office-scope and billing suite: **77 tests, 558 assertions, no failures/errors** before the final added payload-size assertion. The final two-test drill-down/projection check is recorded below.
- Route inventory: **123 API route definitions**, including **90 GET routes**. Every GET route was requested as admin, office staff and JJ, with appropriate synthetic IDs for detail/photo/download routes: **270 API requests**. Non-GET behavior is exercised by the existing API test suite; this audit does not claim every possible write payload was tested.
- Listed pages and seven actual JJ drill-downs add 46 requests: **316 requests total**. **304 returned 200**; nine returned 403, two redirected, and one returned 422. No 500 responses or exceptions. Non-200 outcomes are retained; the audit does not grant permission to make restricted routes return 200.
- Same fixture shapes and roles were run with the original controllers. Status outcomes matched for every route after normalizing synthetic numeric record IDs. Status parity is not full JSON-body equivalence; regression tests separately check calculations, matching and permissions.

## Local performance evidence and limits

In the initial role workload (30 targets, 30 farmers, 15 training records), JJ mapped-villages queries dropped **24 to 14**, allocations **28,544 to 9,698**, and one measured request **25.28 ms to 10.82 ms**. Other routes did not consistently improve in this small sequential workload; compilation, cache warmth and scheduling affect these measurements. Do not infer production latency or a universal speed-up from this table.

The final workload also includes one final-approved bill with populated bill items, five activity/form records and a 100 KB signature. External HTTP is disabled, so these timings exclude real upstream latency. Reads run sequentially; production data volume, cold-cache latency, CPU/IO/locking and concurrent requests remain unmeasured here. The supplied production logs confirm upstream timeouts but cannot alone establish the database wait cause.

Reproduce: `RAILS_ENV=test DATABASE_PORT=55432 bundle exec rails runner script/slow_page_role_audit.rb` against an isolated test database. Writes for fixtures are rolled back; no outbound external HTTP is allowed by this script. The script outputs metrics and a complete API route inventory.

For production verification, deploy the reviewed code and run `bash script/performance_runtime_snapshot.sh javika_production 6` while opening affected pages. Check actual Puma concurrency (the supplied logs show five threads), CPU/memory, DB wait events and Nginx errors. No production connection or deployment was performed in this workspace.

## Final request measurements

These are local synthetic-data measurements, not promised production response times. Dynamic numeric path IDs below refer only to rolled-back test records.

| Role | Route | Status | ms | Queries | Allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| admin | `/dashboard` | 200 | 125.77 | 45 | 81471 |
| admin | `/target_mappings` | 200 | 19.71 | 12 | 16736 |
| admin | `/modules/training-form` | 200 | 66.54 | 18 | 33226 |
| admin | `/modules/training-form-list` | 200 | 38.83 | 9 | 36136 |
| admin | `/modules/other-target` | 200 | 15.72 | 16 | 12990 |
| admin | `/modules/other-target-list` | 200 | 8.02 | 8 | 7155 |
| admin | `/modules/other-target-with-farmer` | 200 | 16.75 | 18 | 17828 |
| admin | `/modules/other-target-with-farmer-list` | 200 | 6.75 | 8 | 6965 |
| admin | `/modules/lg-directory-list` | 200 | 6.91 | 7 | 6074 |
| admin | `/modules/jeevika-jankar-bill-process` | 200 | 26.39 | 23 | 43881 |
| admin | `/modules/jeevika-jankar-bill-list` | 200 | 31.88 | 27 | 46246 |
| admin | `/modules/jeevika-jankar-payment-list` | 200 | 54.81 | 26 | 45378 |
| admin | `/modules/jeevika-jankar-completed-payment-list` | 200 | 8.76 | 8 | 5993 |
| admin | `/api/v1/me` | 200 | 6.54 | 1 | 5479 |
| admin | `/api/v1/user-dashboard` | 200 | 24.71 | 28 | 25389 |
| admin | `/api/v1/jeevika-jankar-dashboard` | 200 | 9.74 | 8 | 8885 |
| admin | `/api/v1/jeevika-jankar-bills` | 200 | 7.27 | 8 | 4509 |
| admin | `/api/v1/jeevika-jankar-payments` | 200 | 6.56 | 7 | 3745 |
| admin | `/api/v1/jeevika-jankar-payments/export` | 200 | 6.19 | 6 | 4641 |
| admin | `/api/v1/jeevika-jankar-payment-details` | 200 | 3.79 | 5 | 2536 |
| admin | `/api/v1/jeevika-jankar-completed-payments` | 200 | 2.91 | 3 | 1873 |
| admin | `/api/v1/sidebar-menus` | 200 | 2.72 | 1 | 3102 |
| admin | `/api/v1/target-mappings/recent` | 200 | 7.41 | 6 | 7216 |
| admin | `/api/v1/jeevika-jankars/form-options` | 200 | 10.54 | 16 | 7379 |
| admin | `/api/v1/jeevika-jankars/approvals` | 200 | 10.69 | 10 | 5203 |
| admin | `/api/v1/jeevika-jankars` | 200 | 9.7 | 12 | 3982 |
| admin | `/api/v1/jeevika-jankar-types` | 200 | 6.69 | 2 | 2677 |
| admin | `/api/v1/jeevika-jankar-masters/all-list` | 200 | 4.98 | 2 | 1438 |
| admin | `/api/v1/jeevika-jankar-masters/states` | 200 | 3.76 | 2 | 1436 |
| admin | `/api/v1/jeevika-jankar-masters/districts` | 200 | 3.12 | 2 | 1435 |
| admin | `/api/v1/jeevika-jankar-masters/blocks` | 200 | 3.12 | 2 | 1435 |
| admin | `/api/v1/jeevika-jankar-masters/gram-panchayats` | 200 | 3.96 | 2 | 1438 |
| admin | `/api/v1/jeevika-jankar-masters/villages` | 200 | 3.29 | 2 | 1435 |
| admin | `/api/v1/jeevika-jankar-masters/months` | 200 | 3.45 | 2 | 1435 |
| admin | `/api/v1/jeevika-jankar-masters/parent-offices` | 200 | 3.99 | 2 | 1438 |
| admin | `/api/v1/jeevika-jankar-masters/office-categories` | 200 | 4.19 | 2 | 1439 |
| admin | `/api/v1/jeevika-jankar-masters/sub-offices` | 200 | 4.18 | 2 | 1438 |
| admin | `/api/v1/jeevika-jankar-masters/cluster-incharges` | 200 | 6.48 | 3 | 2004 |
| admin | `/api/v1/training-forms/form-options` | 200 | 22.4 | 14 | 12287 |
| admin | `/api/v1/training-forms/form-data` | 200 | 13.83 | 14 | 9595 |
| admin | `/api/v1/training-forms/months` | 200 | 2.79 | 3 | 2025 |
| admin | `/api/v1/training-forms/farmers` | 200 | 7.6 | 6 | 7047 |
| admin | `/api/v1/training-forms/mapped-farmers` | 200 | 6.91 | 6 | 6979 |
| admin | `/api/v1/training-forms` | 200 | 2.55 | 2 | 3010 |
| admin | `/api/v1/training-form-list` | 200 | 2.91 | 2 | 2991 |
| admin | `/api/v1/training-form-list/form-options` | 200 | 9.77 | 14 | 9312 |
| admin | `/api/v1/training-form-list/form-data` | 200 | 10.49 | 14 | 9543 |
| admin | `/api/v1/training-form-list/months` | 200 | 2.7 | 3 | 2019 |
| admin | `/api/v1/training-form-list/farmers` | 200 | 7.2 | 6 | 6949 |
| admin | `/api/v1/training-form-list/mapped-farmers` | 200 | 7.56 | 6 | 6979 |
| admin | `/api/v1/farmer-trainings/form-options` | 200 | 10.78 | 14 | 10033 |
| admin | `/api/v1/farmer-trainings/form-data` | 200 | 11.0 | 14 | 9564 |
| admin | `/api/v1/farmer-trainings/months` | 200 | 2.26 | 3 | 2019 |
| admin | `/api/v1/farmer-trainings/farmers` | 200 | 7.76 | 6 | 6920 |
| admin | `/api/v1/farmer-trainings/mapped-farmers` | 200 | 6.73 | 6 | 6994 |
| admin | `/api/v1/farmer-trainings` | 200 | 2.61 | 2 | 2994 |
| admin | `/api/v1/seed-distribution-targets/form-options` | 200 | 7.12 | 9 | 6903 |
| admin | `/api/v1/seed-distribution-targets` | 200 | 2.14 | 2 | 1483 |
| admin | `/api/v1/papl360-targets/form-options` | 200 | 6.34 | 9 | 6868 |
| admin | `/api/v1/papl360-targets` | 200 | 1.88 | 2 | 1457 |
| admin | `/api/v1/other-targets/form-options` | 200 | 6.89 | 9 | 6931 |
| admin | `/api/v1/other-targets/form-data` | 200 | 5.97 | 9 | 5963 |
| admin | `/api/v1/other-targets/months` | 200 | 3.12 | 5 | 3030 |
| admin | `/api/v1/other-targets` | 200 | 2.06 | 2 | 1457 |
| admin | `/api/v1/other-target-list` | 200 | 8.97 | 2 | 1458 |
| admin | `/api/v1/other-target-list/form-options` | 200 | 7.06 | 9 | 5937 |
| admin | `/api/v1/other-target-list/form-data` | 200 | 6.55 | 9 | 5963 |
| admin | `/api/v1/other-target-list/months` | 200 | 3.64 | 5 | 3029 |
| admin | `/api/v1/other-forms/form-options` | 200 | 5.91 | 9 | 5935 |
| admin | `/api/v1/other-forms/form-data` | 200 | 5.93 | 9 | 5958 |
| admin | `/api/v1/other-forms/months` | 200 | 3.17 | 5 | 3032 |
| admin | `/api/v1/other-forms` | 200 | 1.86 | 2 | 1454 |
| admin | `/api/v1/other-target-with-farmers/form-options` | 200 | 6.58 | 9 | 6997 |
| admin | `/api/v1/other-target-with-farmers/form-data` | 200 | 6.34 | 9 | 6012 |
| admin | `/api/v1/other-target-with-farmers/months` | 200 | 3.13 | 5 | 3077 |
| admin | `/api/v1/other-target-with-farmers/farmers` | 200 | 5.31 | 6 | 3743 |
| admin | `/api/v1/other-target-with-farmers` | 200 | 2.38 | 2 | 1507 |
| admin | `/api/v1/other-target-with-farmer-list` | 200 | 2.0 | 2 | 1504 |
| admin | `/api/v1/add-farmer-forms/form-options` | 200 | 4.89 | 3 | 4093 |
| admin | `/api/v1/add-farmer-forms` | 200 | 2.45 | 2 | 1482 |
| admin | `/api/v1/jj-mapped-farmers/jeevika-jankars` | 200 | 2.96 | 1 | 2596 |
| admin | `/api/v1/jj-mapped-farmers/filters` | 200 | 1.45 | 1 | 1229 |
| admin | `/api/v1/jj-mapped-farmers` | 200 | 1.77 | 1 | 1300 |
| admin | `/api/v1/jeevika-jankar-bills/27978/download` | 200 | 7.29 | 11 | 4659 |
| admin | `/api/v1/jeevika-jankar-bills/27978` | 200 | 5.89 | 11 | 4268 |
| admin | `/api/v1/jeevika-jankars/2278` | 200 | 13.01 | 16 | 7458 |
| admin | `/api/v1/training-forms/27958/photos` | 200 | 3.17 | 2 | 1384 |
| admin | `/api/v1/training-forms/27958` | 200 | 1.97 | 2 | 1423 |
| admin | `/api/v1/training-form-list/27958/photos` | 200 | 1.74 | 2 | 1379 |
| admin | `/api/v1/training-form-list/27958` | 200 | 1.97 | 2 | 1420 |
| admin | `/api/v1/farmer-trainings/27958/photos` | 200 | 1.85 | 2 | 1381 |
| admin | `/api/v1/farmer-trainings/27958` | 200 | 1.99 | 2 | 1422 |
| admin | `/api/v1/seed-distribution-targets/27973` | 200 | 1.77 | 2 | 1423 |
| admin | `/api/v1/papl360-targets/27974` | 200 | 1.75 | 2 | 1398 |
| admin | `/api/v1/other-targets/27975/photos` | 200 | 1.61 | 2 | 1371 |
| admin | `/api/v1/other-targets/27975` | 200 | 1.74 | 2 | 1397 |
| admin | `/api/v1/other-target-list/27975/photos` | 200 | 1.65 | 2 | 1370 |
| admin | `/api/v1/other-target-list/27975` | 200 | 1.55 | 2 | 1395 |
| admin | `/api/v1/other-forms/27975` | 200 | 1.78 | 2 | 1395 |
| admin | `/api/v1/other-target-with-farmers/27976/photos` | 200 | 1.71 | 2 | 1419 |
| admin | `/api/v1/other-target-with-farmers/27976` | 200 | 1.66 | 2 | 1446 |
| admin | `/api/v1/other-target-with-farmer-list/27976` | 200 | 1.54 | 2 | 1444 |
| admin | `/api/v1/add-farmer-forms/27977` | 200 | 1.68 | 2 | 1422 |
| staff | `/dashboard` | 200 | 64.15 | 43 | 79799 |
| staff | `/target_mappings` | 200 | 10.12 | 14 | 7334 |
| staff | `/modules/training-form` | 403 | 2.59 | 1 | 1864 |
| staff | `/modules/training-form-list` | 403 | 2.55 | 1 | 1817 |
| staff | `/modules/other-target` | 403 | 2.2 | 1 | 1788 |
| staff | `/modules/other-target-list` | 403 | 2.35 | 1 | 1773 |
| staff | `/modules/other-target-with-farmer` | 200 | 18.61 | 24 | 19165 |
| staff | `/modules/other-target-with-farmer-list` | 200 | 9.08 | 14 | 7666 |
| staff | `/modules/lg-directory-list` | 200 | 6.42 | 7 | 5075 |
| staff | `/modules/jeevika-jankar-bill-process` | 200 | 29.19 | 31 | 45342 |
| staff | `/modules/jeevika-jankar-bill-list` | 200 | 36.78 | 36 | 46996 |
| staff | `/modules/jeevika-jankar-payment-list` | 302 | 2.59 | 1 | 1893 |
| staff | `/modules/jeevika-jankar-completed-payment-list` | 302 | 2.77 | 1 | 1891 |
| staff | `/api/v1/me` | 200 | 1.54 | 1 | 1138 |
| staff | `/api/v1/user-dashboard` | 200 | 34.15 | 55 | 33765 |
| staff | `/api/v1/jeevika-jankar-dashboard` | 422 | 1.71 | 1 | 1178 |
| staff | `/api/v1/jeevika-jankar-bills` | 200 | 5.35 | 9 | 3590 |
| staff | `/api/v1/jeevika-jankar-payments` | 403 | 2.6 | 2 | 1667 |
| staff | `/api/v1/jeevika-jankar-payments/export` | 403 | 2.47 | 2 | 1670 |
| staff | `/api/v1/jeevika-jankar-payment-details` | 403 | 2.67 | 2 | 1665 |
| staff | `/api/v1/jeevika-jankar-completed-payments` | 403 | 3.2 | 2 | 1665 |
| staff | `/api/v1/sidebar-menus` | 200 | 3.55 | 2 | 2455 |
| staff | `/api/v1/target-mappings/recent` | 200 | 2.65 | 2 | 1598 |
| staff | `/api/v1/jeevika-jankars/form-options` | 200 | 7.09 | 15 | 4295 |
| staff | `/api/v1/jeevika-jankars/approvals` | 200 | 7.22 | 12 | 4134 |
| staff | `/api/v1/jeevika-jankars` | 200 | 12.79 | 22 | 7623 |
| staff | `/api/v1/jeevika-jankar-types` | 200 | 2.76 | 2 | 1402 |
| staff | `/api/v1/jeevika-jankar-masters/all-list` | 200 | 2.49 | 2 | 1407 |
| staff | `/api/v1/jeevika-jankar-masters/states` | 200 | 2.12 | 2 | 1404 |
| staff | `/api/v1/jeevika-jankar-masters/districts` | 200 | 2.99 | 2 | 1404 |
| staff | `/api/v1/jeevika-jankar-masters/blocks` | 200 | 2.05 | 2 | 1404 |
| staff | `/api/v1/jeevika-jankar-masters/gram-panchayats` | 200 | 2.22 | 2 | 1407 |
| staff | `/api/v1/jeevika-jankar-masters/villages` | 200 | 2.09 | 2 | 1404 |
| staff | `/api/v1/jeevika-jankar-masters/months` | 200 | 1.96 | 2 | 1404 |
| staff | `/api/v1/jeevika-jankar-masters/parent-offices` | 200 | 2.25 | 2 | 1407 |
| staff | `/api/v1/jeevika-jankar-masters/office-categories` | 200 | 2.18 | 2 | 1408 |
| staff | `/api/v1/jeevika-jankar-masters/sub-offices` | 200 | 1.99 | 2 | 1407 |
| staff | `/api/v1/jeevika-jankar-masters/cluster-incharges` | 200 | 2.69 | 3 | 1942 |
| staff | `/api/v1/training-forms/form-options` | 200 | 10.48 | 15 | 10300 |
| staff | `/api/v1/training-forms/form-data` | 200 | 10.34 | 15 | 10517 |
| staff | `/api/v1/training-forms/months` | 200 | 3.28 | 4 | 2498 |
| staff | `/api/v1/training-forms/farmers` | 200 | 6.9 | 7 | 7398 |
| staff | `/api/v1/training-forms/mapped-farmers` | 200 | 10.78 | 7 | 7514 |
| staff | `/api/v1/training-forms` | 200 | 3.29 | 2 | 2968 |
| staff | `/api/v1/training-form-list` | 200 | 3.09 | 2 | 2964 |
| staff | `/api/v1/training-form-list/form-options` | 200 | 11.23 | 15 | 10289 |
| staff | `/api/v1/training-form-list/form-data` | 200 | 10.92 | 15 | 10551 |
| staff | `/api/v1/training-form-list/months` | 200 | 3.55 | 4 | 2499 |
| staff | `/api/v1/training-form-list/farmers` | 200 | 7.08 | 7 | 7393 |
| staff | `/api/v1/training-form-list/mapped-farmers` | 200 | 7.45 | 7 | 7453 |
| staff | `/api/v1/farmer-trainings/form-options` | 200 | 10.1 | 15 | 10287 |
| staff | `/api/v1/farmer-trainings/form-data` | 200 | 10.87 | 15 | 10518 |
| staff | `/api/v1/farmer-trainings/months` | 200 | 2.83 | 4 | 2498 |
| staff | `/api/v1/farmer-trainings/farmers` | 200 | 6.93 | 7 | 7393 |
| staff | `/api/v1/farmer-trainings/mapped-farmers` | 200 | 6.97 | 7 | 7453 |
| staff | `/api/v1/farmer-trainings` | 200 | 2.64 | 2 | 2965 |
| staff | `/api/v1/seed-distribution-targets/form-options` | 200 | 7.18 | 10 | 6937 |
| staff | `/api/v1/seed-distribution-targets` | 200 | 2.14 | 2 | 1454 |
| staff | `/api/v1/papl360-targets/form-options` | 200 | 6.06 | 10 | 6909 |
| staff | `/api/v1/papl360-targets` | 200 | 1.92 | 2 | 1428 |
| staff | `/api/v1/other-targets/form-options` | 200 | 5.7 | 10 | 6910 |
| staff | `/api/v1/other-targets/form-data` | 200 | 5.9 | 10 | 6933 |
| staff | `/api/v1/other-targets/months` | 200 | 3.22 | 6 | 3508 |
| staff | `/api/v1/other-targets` | 200 | 1.8 | 2 | 1428 |
| staff | `/api/v1/other-target-list` | 200 | 1.65 | 2 | 1428 |
| staff | `/api/v1/other-target-list/form-options` | 200 | 6.08 | 10 | 6910 |
| staff | `/api/v1/other-target-list/form-data` | 200 | 8.71 | 10 | 6933 |
| staff | `/api/v1/other-target-list/months` | 200 | 4.07 | 6 | 3513 |
| staff | `/api/v1/other-forms/form-options` | 200 | 7.3 | 10 | 6912 |
| staff | `/api/v1/other-forms/form-data` | 200 | 6.88 | 10 | 6937 |
| staff | `/api/v1/other-forms/months` | 200 | 3.42 | 6 | 3508 |
| staff | `/api/v1/other-forms` | 200 | 1.94 | 2 | 1431 |
| staff | `/api/v1/other-target-with-farmers/form-options` | 200 | 6.65 | 10 | 6957 |
| staff | `/api/v1/other-target-with-farmers/form-data` | 200 | 6.25 | 10 | 6980 |
| staff | `/api/v1/other-target-with-farmers/months` | 200 | 3.5 | 6 | 3557 |
| staff | `/api/v1/other-target-with-farmers/farmers` | 200 | 5.03 | 7 | 4110 |
| staff | `/api/v1/other-target-with-farmers` | 200 | 1.9 | 2 | 1478 |
| staff | `/api/v1/other-target-with-farmer-list` | 200 | 1.67 | 2 | 1477 |
| staff | `/api/v1/add-farmer-forms/form-options` | 200 | 4.01 | 5 | 3711 |
| staff | `/api/v1/add-farmer-forms` | 200 | 1.87 | 2 | 1452 |
| staff | `/api/v1/jj-mapped-farmers/jeevika-jankars` | 200 | 2.62 | 2 | 2031 |
| staff | `/api/v1/jj-mapped-farmers/filters` | 200 | 1.52 | 1 | 1194 |
| staff | `/api/v1/jj-mapped-farmers` | 200 | 2.91 | 2 | 2466 |
| staff | `/api/v1/jeevika-jankar-bills/27978/download` | 200 | 6.41 | 12 | 4891 |
| staff | `/api/v1/jeevika-jankar-bills/27978` | 200 | 5.91 | 12 | 4651 |
| staff | `/api/v1/jeevika-jankars/2278` | 200 | 13.79 | 26 | 10013 |
| staff | `/api/v1/training-forms/27958/photos` | 200 | 2.76 | 3 | 1921 |
| staff | `/api/v1/training-forms/27958` | 200 | 2.71 | 3 | 1954 |
| staff | `/api/v1/training-form-list/27958/photos` | 200 | 3.48 | 3 | 1909 |
| staff | `/api/v1/training-form-list/27958` | 200 | 2.46 | 3 | 1953 |
| staff | `/api/v1/farmer-trainings/27958/photos` | 200 | 2.31 | 3 | 1909 |
| staff | `/api/v1/farmer-trainings/27958` | 200 | 2.31 | 3 | 1954 |
| staff | `/api/v1/seed-distribution-targets/27973` | 200 | 2.32 | 3 | 1954 |
| staff | `/api/v1/papl360-targets/27974` | 200 | 2.31 | 3 | 1929 |
| staff | `/api/v1/other-targets/27975/photos` | 200 | 2.15 | 3 | 1900 |
| staff | `/api/v1/other-targets/27975` | 200 | 2.3 | 3 | 1929 |
| staff | `/api/v1/other-target-list/27975/photos` | 200 | 2.21 | 3 | 1900 |
| staff | `/api/v1/other-target-list/27975` | 200 | 2.56 | 3 | 1928 |
| staff | `/api/v1/other-forms/27975` | 200 | 2.84 | 3 | 1928 |
| staff | `/api/v1/other-target-with-farmers/27976/photos` | 200 | 2.67 | 3 | 1948 |
| staff | `/api/v1/other-target-with-farmers/27976` | 200 | 2.68 | 3 | 1978 |
| staff | `/api/v1/other-target-with-farmer-list/27976` | 200 | 2.44 | 3 | 1977 |
| staff | `/api/v1/add-farmer-forms/27977` | 200 | 2.45 | 3 | 1953 |
| jj | `/dashboard` | 200 | 54.92 | 36 | 65485 |
| jj | `/target_mappings` | 200 | 14.44 | 15 | 11319 |
| jj | `/modules/training-form` | 200 | 16.09 | 18 | 18448 |
| jj | `/modules/training-form-list` | 200 | 19.84 | 16 | 39743 |
| jj | `/modules/other-target` | 200 | 16.7 | 24 | 17030 |
| jj | `/modules/other-target-list` | 200 | 13.95 | 15 | 10753 |
| jj | `/modules/other-target-with-farmer` | 200 | 21.62 | 26 | 20306 |
| jj | `/modules/other-target-with-farmer-list` | 200 | 9.79 | 15 | 9029 |
| jj | `/modules/lg-directory-list` | 200 | 8.86 | 11 | 7379 |
| jj | `/modules/jeevika-jankar-bill-process` | 200 | 31.95 | 35 | 47822 |
| jj | `/modules/jeevika-jankar-bill-list` | 200 | 31.62 | 38 | 48942 |
| jj | `/modules/jeevika-jankar-payment-list` | 200 | 37.92 | 37 | 50540 |
| jj | `/modules/jeevika-jankar-completed-payment-list` | 200 | 9.66 | 12 | 9163 |
| jj | `/dashboard/vrp-list/assigned_farmers` | 200 | 29.94 | 23 | 50284 |
| jj | `/dashboard/vrp-list/assigned_target` | 200 | 26.63 | 22 | 47637 |
| jj | `/dashboard/vrp-list/mapped_villages` | 200 | 10.18 | 14 | 9628 |
| jj | `/dashboard/vrp-list/pending_target` | 200 | 31.91 | 22 | 46403 |
| jj | `/dashboard/vrp-list/achieved_target` | 200 | 27.37 | 22 | 46360 |
| jj | `/dashboard/vrp-list/main_activities` | 200 | 25.27 | 22 | 45247 |
| jj | `/dashboard/vrp-list/sub_activities` | 200 | 29.82 | 22 | 45503 |
| jj | `/api/v1/me` | 200 | 2.87 | 3 | 1711 |
| jj | `/api/v1/user-dashboard` | 403 | 1.69 | 1 | 1291 |
| jj | `/api/v1/jeevika-jankar-dashboard` | 200 | 24.75 | 26 | 43391 |
| jj | `/api/v1/jeevika-jankar-bills` | 200 | 6.53 | 12 | 4438 |
| jj | `/api/v1/jeevika-jankar-payments` | 200 | 6.72 | 10 | 5551 |
| jj | `/api/v1/jeevika-jankar-payments/export` | 200 | 6.6 | 9 | 6100 |
| jj | `/api/v1/jeevika-jankar-payment-details` | 200 | 5.6 | 8 | 4793 |
| jj | `/api/v1/jeevika-jankar-completed-payments` | 200 | 5.06 | 6 | 4153 |
| jj | `/api/v1/sidebar-menus` | 200 | 3.96 | 4 | 3992 |
| jj | `/api/v1/target-mappings/recent` | 200 | 6.74 | 8 | 6676 |
| jj | `/api/v1/jeevika-jankars/form-options` | 200 | 8.12 | 21 | 5408 |
| jj | `/api/v1/jeevika-jankars/approvals` | 200 | 7.15 | 14 | 4681 |
| jj | `/api/v1/jeevika-jankars` | 200 | 14.2 | 24 | 8069 |
| jj | `/api/v1/jeevika-jankar-types` | 200 | 2.63 | 2 | 1586 |
| jj | `/api/v1/jeevika-jankar-masters/all-list` | 200 | 2.73 | 2 | 1592 |
| jj | `/api/v1/jeevika-jankar-masters/states` | 200 | 2.54 | 2 | 1589 |
| jj | `/api/v1/jeevika-jankar-masters/districts` | 200 | 4.01 | 2 | 1589 |
| jj | `/api/v1/jeevika-jankar-masters/blocks` | 200 | 3.47 | 2 | 1589 |
| jj | `/api/v1/jeevika-jankar-masters/gram-panchayats` | 200 | 2.84 | 2 | 1592 |
| jj | `/api/v1/jeevika-jankar-masters/villages` | 200 | 5.13 | 2 | 1589 |
| jj | `/api/v1/jeevika-jankar-masters/months` | 200 | 5.63 | 2 | 1589 |
| jj | `/api/v1/jeevika-jankar-masters/parent-offices` | 200 | 4.02 | 2 | 1592 |
| jj | `/api/v1/jeevika-jankar-masters/office-categories` | 200 | 3.68 | 2 | 1593 |
| jj | `/api/v1/jeevika-jankar-masters/sub-offices` | 200 | 3.69 | 2 | 1592 |
| jj | `/api/v1/jeevika-jankar-masters/cluster-incharges` | 200 | 7.94 | 8 | 2865 |
| jj | `/api/v1/training-forms/form-options` | 200 | 16.34 | 14 | 9431 |
| jj | `/api/v1/training-forms/form-data` | 200 | 18.16 | 14 | 9679 |
| jj | `/api/v1/training-forms/months` | 200 | 9.78 | 6 | 2981 |
| jj | `/api/v1/training-forms/farmers` | 200 | 12.92 | 9 | 7888 |
| jj | `/api/v1/training-forms/mapped-farmers` | 200 | 8.66 | 9 | 7931 |
| jj | `/api/v1/training-forms` | 200 | 4.66 | 5 | 4519 |
| jj | `/api/v1/training-form-list` | 200 | 5.51 | 5 | 4521 |
| jj | `/api/v1/training-form-list/form-options` | 200 | 10.0 | 14 | 9426 |
| jj | `/api/v1/training-form-list/form-data` | 200 | 10.03 | 14 | 9668 |
| jj | `/api/v1/training-form-list/months` | 200 | 4.12 | 6 | 2976 |
| jj | `/api/v1/training-form-list/farmers` | 200 | 8.31 | 9 | 7871 |
| jj | `/api/v1/training-form-list/mapped-farmers` | 200 | 8.59 | 9 | 7946 |
| jj | `/api/v1/farmer-trainings/form-options` | 200 | 12.25 | 14 | 9427 |
| jj | `/api/v1/farmer-trainings/form-data` | 200 | 12.75 | 14 | 9679 |
| jj | `/api/v1/farmer-trainings/months` | 200 | 4.61 | 6 | 2977 |
| jj | `/api/v1/farmer-trainings/farmers` | 200 | 8.22 | 9 | 7886 |
| jj | `/api/v1/farmer-trainings/mapped-farmers` | 200 | 8.41 | 9 | 7931 |
| jj | `/api/v1/farmer-trainings` | 200 | 5.4 | 5 | 4518 |
| jj | `/api/v1/seed-distribution-targets/form-options` | 200 | 7.48 | 10 | 6302 |
| jj | `/api/v1/seed-distribution-targets` | 200 | 3.97 | 5 | 2447 |
| jj | `/api/v1/papl360-targets/form-options` | 200 | 6.88 | 10 | 6278 |
| jj | `/api/v1/papl360-targets` | 200 | 6.9 | 5 | 2424 |
| jj | `/api/v1/other-targets/form-options` | 200 | 8.46 | 10 | 6280 |
| jj | `/api/v1/other-targets/form-data` | 200 | 8.64 | 10 | 6304 |
| jj | `/api/v1/other-targets/months` | 200 | 5.78 | 8 | 3986 |
| jj | `/api/v1/other-targets` | 200 | 4.51 | 5 | 2422 |
| jj | `/api/v1/other-target-list` | 200 | 4.48 | 5 | 2424 |
| jj | `/api/v1/other-target-list/form-options` | 200 | 8.38 | 10 | 6277 |
| jj | `/api/v1/other-target-list/form-data` | 200 | 8.28 | 10 | 6301 |
| jj | `/api/v1/other-target-list/months` | 200 | 5.56 | 8 | 3987 |
| jj | `/api/v1/other-forms/form-options` | 200 | 8.0 | 10 | 6277 |
| jj | `/api/v1/other-forms/form-data` | 200 | 7.47 | 10 | 6300 |
| jj | `/api/v1/other-forms/months` | 200 | 6.01 | 8 | 3986 |
| jj | `/api/v1/other-forms` | 200 | 5.58 | 5 | 2421 |
| jj | `/api/v1/other-target-with-farmers/form-options` | 200 | 8.49 | 10 | 6325 |
| jj | `/api/v1/other-target-with-farmers/form-data` | 200 | 8.76 | 10 | 6347 |
| jj | `/api/v1/other-target-with-farmers/months` | 200 | 5.57 | 8 | 4034 |
| jj | `/api/v1/other-target-with-farmers/farmers` | 200 | 8.37 | 9 | 4584 |
| jj | `/api/v1/other-target-with-farmers` | 200 | 4.06 | 5 | 2472 |
| jj | `/api/v1/other-target-with-farmer-list` | 200 | 3.91 | 5 | 2471 |
| jj | `/api/v1/add-farmer-forms/form-options` | 200 | 5.45 | 6 | 4072 |
| jj | `/api/v1/add-farmer-forms` | 200 | 4.34 | 5 | 2446 |
| jj | `/api/v1/jj-mapped-farmers/jeevika-jankars` | 200 | 3.93 | 3 | 1767 |
| jj | `/api/v1/jj-mapped-farmers/filters` | 200 | 3.38 | 3 | 1757 |
| jj | `/api/v1/jj-mapped-farmers` | 200 | 3.56 | 3 | 1860 |
| jj | `/api/v1/jeevika-jankar-bills/27978/download` | 200 | 9.22 | 14 | 5543 |
| jj | `/api/v1/jeevika-jankar-bills/27978` | 200 | 7.51 | 14 | 5303 |
| jj | `/api/v1/jeevika-jankars/2278` | 200 | 18.43 | 27 | 10675 |
| jj | `/api/v1/training-forms/27958/photos` | 200 | 5.27 | 5 | 2344 |
| jj | `/api/v1/training-forms/27958` | 200 | 5.17 | 5 | 2384 |
| jj | `/api/v1/training-form-list/27958/photos` | 200 | 4.46 | 5 | 2339 |
| jj | `/api/v1/training-form-list/27958` | 200 | 7.53 | 5 | 2387 |
| jj | `/api/v1/farmer-trainings/27958/photos` | 200 | 6.87 | 5 | 2339 |
| jj | `/api/v1/farmer-trainings/27958` | 200 | 4.59 | 5 | 2384 |
| jj | `/api/v1/seed-distribution-targets/27973` | 200 | 4.52 | 5 | 2384 |
| jj | `/api/v1/papl360-targets/27974` | 200 | 3.85 | 5 | 2362 |
| jj | `/api/v1/other-targets/27975/photos` | 200 | 3.46 | 5 | 2330 |
| jj | `/api/v1/other-targets/27975` | 200 | 4.24 | 5 | 2359 |
| jj | `/api/v1/other-target-list/27975/photos` | 200 | 4.24 | 5 | 2330 |
| jj | `/api/v1/other-target-list/27975` | 200 | 4.07 | 5 | 2358 |
| jj | `/api/v1/other-forms/27975` | 200 | 3.59 | 5 | 2359 |
| jj | `/api/v1/other-target-with-farmers/27976/photos` | 200 | 4.69 | 5 | 2378 |
| jj | `/api/v1/other-target-with-farmers/27976` | 200 | 5.45 | 5 | 2409 |
| jj | `/api/v1/other-target-with-farmer-list/27976` | 200 | 4.38 | 5 | 2407 |
| jj | `/api/v1/add-farmer-forms/27977` | 200 | 4.27 | 5 | 2383 |

## API route inventory

All GET definitions below were probed for three roles. Other methods were not automatically invoked by the read audit.

| Method | Route |
| --- | --- |
| POST | `/api/v1/login` |
| POST | `/api/v1/jeevika-jankar-login` |
| POST | `/api/v1/login/otp/send` |
| POST | `/api/v1/login/otp/verify` |
| POST | `/api/v1/forgot-password/send-otp` |
| POST | `/api/v1/forgot-password/reset` |
| GET | `/api/v1/me` |
| GET | `/api/v1/user-dashboard` |
| GET | `/api/v1/jeevika-jankar-dashboard` |
| GET | `/api/v1/jeevika-jankar-bills` |
| GET | `/api/v1/jeevika-jankar-bills/:id/download` |
| GET | `/api/v1/jeevika-jankar-bills/:id` |
| PATCH | `/api/v1/jeevika-jankar-bills/:id/send-for-approval` |
| PATCH | `/api/v1/jeevika-jankar-bills/:id/approve` |
| PATCH | `/api/v1/jeevika-jankar-bills/:id/reject` |
| PATCH | `/api/v1/jeevika-jankar-bills/:id/return` |
| GET | `/api/v1/jeevika-jankar-payments` |
| GET | `/api/v1/jeevika-jankar-payments/export` |
| GET | `/api/v1/jeevika-jankar-payment-details` |
| GET | `/api/v1/jeevika-jankar-completed-payments` |
| GET | `/api/v1/sidebar-menus` |
| GET | `/api/v1/target-mappings/recent` |
| DELETE | `/api/v1/logout` |
| GET | `/api/v1/jeevika-jankars/form-options` |
| GET | `/api/v1/jeevika-jankars/approvals` |
| PATCH | `/api/v1/jeevika-jankars/:id/approve` |
| PATCH | `/api/v1/jeevika-jankars/:id/return` |
| PATCH | `/api/v1/jeevika-jankars/:id/reject` |
| PATCH | `/api/v1/jeevika-jankars/:id/send_for_approval` |
| GET | `/api/v1/jeevika-jankars` |
| POST | `/api/v1/jeevika-jankars` |
| GET | `/api/v1/jeevika-jankars/:id` |
| PATCH | `/api/v1/jeevika-jankars/:id` |
| PUT | `/api/v1/jeevika-jankars/:id` |
| GET | `/api/v1/jeevika-jankar-types` |
| POST | `/api/v1/jeevika-jankar-types` |
| GET | `/api/v1/jeevika-jankar-masters/all-list` |
| GET | `/api/v1/jeevika-jankar-masters/states` |
| GET | `/api/v1/jeevika-jankar-masters/districts` |
| GET | `/api/v1/jeevika-jankar-masters/blocks` |
| GET | `/api/v1/jeevika-jankar-masters/gram-panchayats` |
| GET | `/api/v1/jeevika-jankar-masters/villages` |
| GET | `/api/v1/jeevika-jankar-masters/months` |
| GET | `/api/v1/jeevika-jankar-masters/parent-offices` |
| GET | `/api/v1/jeevika-jankar-masters/office-categories` |
| GET | `/api/v1/jeevika-jankar-masters/sub-offices` |
| GET | `/api/v1/jeevika-jankar-masters/cluster-incharges` |
| GET | `/api/v1/training-forms/form-options` |
| GET | `/api/v1/training-forms/form-data` |
| GET | `/api/v1/training-forms/months` |
| GET | `/api/v1/training-forms/farmers` |
| GET | `/api/v1/training-forms/mapped-farmers` |
| GET | `/api/v1/training-forms/:id/photos` |
| GET | `/api/v1/training-forms` |
| POST | `/api/v1/training-forms` |
| GET | `/api/v1/training-forms/:id` |
| GET | `/api/v1/training-form-list` |
| GET | `/api/v1/training-form-list/form-options` |
| GET | `/api/v1/training-form-list/form-data` |
| GET | `/api/v1/training-form-list/months` |
| GET | `/api/v1/training-form-list/farmers` |
| GET | `/api/v1/training-form-list/mapped-farmers` |
| GET | `/api/v1/training-form-list/:id/photos` |
| GET | `/api/v1/training-form-list/:id` |
| GET | `/api/v1/farmer-trainings/form-options` |
| GET | `/api/v1/farmer-trainings/form-data` |
| GET | `/api/v1/farmer-trainings/months` |
| GET | `/api/v1/farmer-trainings/farmers` |
| GET | `/api/v1/farmer-trainings/mapped-farmers` |
| GET | `/api/v1/farmer-trainings/:id/photos` |
| GET | `/api/v1/farmer-trainings` |
| POST | `/api/v1/farmer-trainings` |
| GET | `/api/v1/farmer-trainings/:id` |
| PATCH | `/api/v1/farmer-trainings/:id` |
| PUT | `/api/v1/farmer-trainings/:id` |
| GET | `/api/v1/seed-distribution-targets/form-options` |
| GET | `/api/v1/seed-distribution-targets` |
| POST | `/api/v1/seed-distribution-targets` |
| GET | `/api/v1/seed-distribution-targets/:id` |
| GET | `/api/v1/papl360-targets/form-options` |
| GET | `/api/v1/papl360-targets` |
| POST | `/api/v1/papl360-targets` |
| GET | `/api/v1/papl360-targets/:id` |
| GET | `/api/v1/other-targets/form-options` |
| GET | `/api/v1/other-targets/form-data` |
| GET | `/api/v1/other-targets/months` |
| GET | `/api/v1/other-targets/:id/photos` |
| GET | `/api/v1/other-targets` |
| POST | `/api/v1/other-targets` |
| GET | `/api/v1/other-targets/:id` |
| PATCH | `/api/v1/other-targets/:id` |
| PUT | `/api/v1/other-targets/:id` |
| GET | `/api/v1/other-target-list` |
| GET | `/api/v1/other-target-list/form-options` |
| GET | `/api/v1/other-target-list/form-data` |
| GET | `/api/v1/other-target-list/months` |
| GET | `/api/v1/other-target-list/:id/photos` |
| GET | `/api/v1/other-target-list/:id` |
| GET | `/api/v1/other-forms/form-options` |
| GET | `/api/v1/other-forms/form-data` |
| GET | `/api/v1/other-forms/months` |
| GET | `/api/v1/other-forms` |
| POST | `/api/v1/other-forms` |
| GET | `/api/v1/other-forms/:id` |
| GET | `/api/v1/other-target-with-farmers/form-options` |
| GET | `/api/v1/other-target-with-farmers/form-data` |
| GET | `/api/v1/other-target-with-farmers/months` |
| GET | `/api/v1/other-target-with-farmers/farmers` |
| GET | `/api/v1/other-target-with-farmers/:id/photos` |
| GET | `/api/v1/other-target-with-farmers` |
| POST | `/api/v1/other-target-with-farmers` |
| GET | `/api/v1/other-target-with-farmers/:id` |
| PATCH | `/api/v1/other-target-with-farmers/:id` |
| PUT | `/api/v1/other-target-with-farmers/:id` |
| GET | `/api/v1/other-target-with-farmer-list` |
| GET | `/api/v1/other-target-with-farmer-list/:id` |
| GET | `/api/v1/add-farmer-forms/form-options` |
| GET | `/api/v1/add-farmer-forms` |
| POST | `/api/v1/add-farmer-forms` |
| GET | `/api/v1/add-farmer-forms/:id` |
| GET | `/api/v1/jj-mapped-farmers/jeevika-jankars` |
| GET | `/api/v1/jj-mapped-farmers/filters` |
| GET | `/api/v1/jj-mapped-farmers` |

Final drill-down/projection check after the payload-size assertion: **two tests, 25 assertions, no failures/errors**. The final approved-bill version of all 316 role requests also had zero status differences versus the original controllers. Ruby syntax and `git diff --check` pass.
