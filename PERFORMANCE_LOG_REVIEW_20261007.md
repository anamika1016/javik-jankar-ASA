# October 7 billing performance review

Requests in the supplied journal were correlated by request ID. Only requests with both a start and completion in the attachment are included. No personal data or authentication parameters are copied here.

| Route | Completed requests | Duration range |
| --- | ---: | ---: |
| Bill list | 4 | 47.861–290.492s |
| Bill process | 5 | 101.770–285.215s |
| Bill target/achievement rows | 9 | 1.136–84.555s |
| Dashboard | 1 | 28.024s |
| Target mapping options | 14 | 0.031–17.391s |
| Target mapping list | 1 | 7.527s |

## Changes

- Reuse approved other-target achievement indexes per candidate target set within a request. Previously, missing achievements triggered another query and deserialization of the same records for every target. Empty indexes are cached too. Different JJ/month candidate sets get separate indexes.
- Reuse training record ID indexes per month instead of rebuilding the same hash for every target/farmer lookup. Shared dashboard and bill calculations benefit.
- Stop fetching bill rows for the dropdown placeholder. Unresolvable JJ selections return empty rows before loading activity/training records.
- Share concurrent bill-row requests for the same JJ/month. Failed requests are removed so retry remains possible.

Calculation, grouping, capping, approval, duplicate-bill and visibility rules remain unchanged. Caches live only for the request/page; no persistent achievement cache was introduced.

## Validation

Read-only local development achievement-key workload: original 2.590s, updated 0.743s. Both returned 113 keys with SHA-256 `46407f88926e0d0689ba67ff522e3a8aa63cddf0ad75a376494ae77703221c55`. Original query capture showed 24 reads of the other-target achievement records. These local timings are not production latency predictions.

38 Rails billing, performance and target regression tests passed with 128 assertions, including the new scope-change/empty-index test. Five JavaScript test files covering bill loading and target mapping passed. JavaScript syntax and `git diff --check` passed.

An existing FCO-count test expects one JJ but sees three in the local test database; the same failure was reproduced using the original controller. The existing language-switch and location-options JavaScript tests also fail with the original layout source (missing DOM mock methods and option expectation mismatches). Those unrelated tests were not changed.

## Production follow-up

No production deploy, restart or database changes were performed. The supplied logs also show very high database time on requests with few queries, and concurrent requests becoming slow together. Aggregate INFO logs cannot distinguish database load, waits, slow SQL plans or host resource pressure. Run the existing read-only `PERFORMANCE_DIAGNOSTICS.sql` during a slow period to inspect waits and index validity before making infrastructure or index changes. Validate request durations after deploying these changes; a five-minute production delay is not proven resolved by local measurements.
