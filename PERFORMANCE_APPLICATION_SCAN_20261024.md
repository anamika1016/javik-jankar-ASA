# Application performance scan — 24 October 2026

This extends PERFORMANCE_INCIDENT_20261024.md. The supplied production incident confirms response-header timeouts; the workspace does not have a supplied production SSH connection. The changes below are local and have not been deployed. Whole-application production performance is not established by this audit.

## Scope and fixes

Read the shared login/session payload path, application layout/sidebar helpers, target mapping reads, achievement matching, form catalogues and external-HTTP call sites in controllers/services. Exercised all configured module screens plus primary web screens and target dashboard drill-down URLs through Rails integration sessions.

- Every authenticated JJ request previously selected the full JJ row, including the signature image, to check active status and rebuild session metadata. Use an explicit signature-free scope for this check. Still read the database on every request, preserve session payload fields, and log out a newly deactivated JJ immediately. Agreement views and stored signatures retain full-record access.
- Target mapping JJ selectors and mapped-farmer staff selectors use the same signature-free scope. Target mapping table rows preload the same JJ associations without image data; mapping groups, order, export fields and access filters remain unchanged.
- Achievement matching previously scanned all candidate targets for each saved activity. Index candidate targets by normalized owner aliases and month, then apply the original ICS, village and activity predicates. Direct saved mapping IDs, name/login aliases, result ordering and empty-candidate fallback remain unchanged. Rebuild when the candidate array changes, including per-bill scope changes. This improves unrelated-owner/month workloads; a single owner/month containing every target can still require a full bucket scan.
- Previous-round fixes retain revision-checked location catalogue reuse and remove signature data from achievement candidate/dashboard summary association loads.
- The audit script now blocks external HTTP by default, adds nine route checks and records allocations. Synthetic test data is rolled back. Explicit PERFORMANCE_AUDIT_EXTERNAL_HTTP=1 enables upstream calls if desired; offline measurements cannot establish upstream latency.

## Measured matching cost

One process, 500 lightweight targets and 500 saved activity records; compare every result to the original full-scan predicate. This measures the helper, not a production request.

| Measurement | Full scan | Indexed |
| --- | ---: | ---: |
| Time | 663.34 ms | 15.80 ms |
| Ruby allocations | 3,787,027 | 56,419 |
| Database queries | 0 | 0 |

Matching was approximately 42 times faster in this synthetic workload. Separate regression tests check legacy aliases/direct IDs, candidate scope changes and one predicate call per matching owner/month rather than 500 calls per activity.

## Route audit

84 sequential local admin GETs: 75 responses with status 200 and nine redirects; no 500/errors. Redirects are reported explicitly and do not count as rendered drill-down screens. These page requests use the small existing test dataset after synthetic helper benchmark records are rolled back. They are not load tests or a replica of production data. Staff/JJ scoping is checked separately by regression tests. Cache warmth, compilation and the absent upstream network make these durations unsuitable as production promises.

Reproduce using `RAILS_ENV=test DATABASE_PORT=55432 bundle exec rails runner script/performance_audit.rb` against an isolated test database. The port should match the local test instance.

| Route | Status | Milliseconds | DB queries | Allocations | Response bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| `/modules/state-master` | 200 | 63.41 | 6 | 29790 | 16750 |
| `/modules/district-master` | 200 | 22.11 | 9 | 8273 | 17123 |
| `/modules/block-master` | 200 | 28.44 | 10 | 8621 | 17431 |
| `/modules/gram-panchayat-master` | 200 | 24.78 | 11 | 9393 | 17853 |
| `/modules/village-master` | 200 | 25.92 | 12 | 10102 | 18175 |
| `/modules/lg-directory-list` | 200 | 20.78 | 7 | 5936 | 17231 |
| `/modules/stakeholder-master` | 200 | 16.49 | 6 | 6415 | 17075 |
| `/modules/stakeholder-profile` | 200 | 19.35 | 6 | 7618 | 18109 |
| `/modules/training-form` | 200 | 46.9 | 19 | 16457 | 34412 |
| `/modules/training-form-list` | 200 | 18.89 | 6 | 6253 | 17155 |
| `/modules/seed-distribution-target` | 200 | 25.32 | 13 | 10942 | 20172 |
| `/modules/seed-distribution-target-list` | 200 | 15.8 | 6 | 5804 | 16194 |
| `/modules/papl360-target` | 200 | 26.73 | 13 | 10693 | 19784 |
| `/modules/papl360-target-list` | 200 | 25.26 | 6 | 5765 | 16062 |
| `/modules/other-target` | 200 | 33.75 | 13 | 10705 | 18934 |
| `/modules/other-target-with-farmer` | 200 | 25.29 | 13 | 10731 | 19918 |
| `/modules/other-target-with-farmer-list` | 200 | 8.65 | 6 | 5711 | 16146 |
| `/modules/other-target-list` | 200 | 8.64 | 6 | 5795 | 16384 |
| `/modules/add-farmer-form` | 200 | 10.86 | 7 | 6655 | 17093 |
| `/modules/training-topic-mapping` | 200 | 8.12 | 5 | 5880 | 17106 |
| `/modules/bank-master` | 200 | 8.98 | 5 | 6317 | 16908 |
| `/modules/month-master` | 200 | 21.8 | 8 | 7435 | 17773 |
| `/modules/project-master` | 200 | 13.65 | 6 | 6011 | 16430 |
| `/modules/activity-master` | 200 | 13.11 | 5 | 5885 | 16452 |
| `/modules/parent-office-add` | 200 | 33.42 | 10 | 9563 | 18466 |
| `/modules/office-category-add` | 200 | 21.84 | 9 | 8345 | 17811 |
| `/modules/office-mapping-add` | 200 | 25.8 | 10 | 9076 | 18078 |
| `/modules/office-list` | 200 | 13.2 | 6 | 5378 | 14601 |
| `/modules/add-vrp-type` | 200 | 13.86 | 5 | 5777 | 16510 |
| `/modules/add-activity-group` | 200 | 28.57 | 8 | 7729 | 17490 |
| `/modules/activity-group-list` | 200 | 13.12 | 6 | 5419 | 15681 |
| `/modules/add-vrp-activity` | 200 | 13.87 | 7 | 7015 | 17021 |
| `/modules/vrp-activity-list` | 200 | 13.82 | 6 | 5466 | 15650 |
| `/modules/task-completion-indicator` | 200 | 18.68 | 8 | 7677 | 17281 |
| `/modules/task-completion-indicator-list` | 200 | 10.62 | 6 | 5435 | 15760 |
| `/modules/task-indicator-master` | 200 | 9.15 | 6 | 6810 | 17063 |
| `/modules/approval-master` | 200 | 7.78 | 7 | 6235 | 19092 |
| `/modules/approval-list` | 200 | 6.0 | 6 | 5278 | 15649 |
| `/modules/ics-master` | 200 | 6.34 | 5 | 5896 | 16382 |
| `/modules/vrp-registration-list` | 200 | 6.71 | 6 | 6512 | 17519 |
| `/modules/vrp-bill-add` | 200 | 11.71 | 13 | 8752 | 17797 |
| `/modules/vrp-bill-list` | 200 | 6.42 | 6 | 5577 | 15755 |
| `/modules/jeevika-jankar-bill-process` | 200 | 16.12 | 18 | 9212 | 26985 |
| `/modules/jeevika-jankar-bill-list` | 200 | 9.67 | 7 | 5835 | 16925 |
| `/modules/jeevika-jankar-observation-list` | 200 | 14.18 | 8 | 6293 | 18212 |
| `/modules/jeevika-jankar-payment-list` | 200 | 9.95 | 8 | 6242 | 15774 |
| `/modules/jeevika-jankar-payment-list-detail` | 200 | 18.38 | 8 | 6100 | 17874 |
| `/modules/jeevika-jankar-completed-payment-list` | 200 | 9.35 | 8 | 5964 | 15912 |
| `/modules/weekly-target-add` | 200 | 25.48 | 19 | 17086 | 22544 |
| `/modules/weekly-target-list` | 200 | 10.79 | 6 | 6781 | 17612 |
| `/modules/weekly-progress-report` | 200 | 8.13 | 5 | 6703 | 17345 |
| `/modules/monthly-bill-summary` | 200 | 15.74 | 7 | 8053 | 18376 |
| `/modules/weekly-activity-progress` | 200 | 10.8 | 6 | 7397 | 17741 |
| `/modules/approval-status-summary` | 200 | 11.63 | 6 | 6992 | 18031 |
| `/modules/payment-status-report` | 200 | 9.33 | 5 | 6790 | 17521 |
| `/modules/new-user` | 302 | 2.02 | 0 | 1278 | 0 |
| `/modules/all-user` | 302 | 1.87 | 0 | 1268 | 0 |
| `/modules/jeevika-jankar-transfer` | 200 | 13.0 | 9 | 8089 | 17051 |
| `/modules/jeevika-jankar-transfer-list` | 200 | 8.62 | 6 | 5659 | 15558 |
| `/modules/user-hierarchy-mapping` | 200 | 12.08 | 8 | 6266 | 17346 |
| `/modules/user-hierarchy-list` | 200 | 10.38 | 8 | 5937 | 16778 |
| `/modules/stakeholder-role` | 200 | 10.01 | 8 | 7489 | 17216 |
| `/modules/role-name` | 200 | 15.41 | 12 | 8275 | 17221 |
| `/modules/access-control` | 200 | 16.34 | 8 | 8612 | 37438 |
| `/modules/access-control-list` | 200 | 8.25 | 6 | 5518 | 15825 |
| `/dashboard` | 200 | 68.72 | 39 | 32570 | 27873 |
| `/users` | 200 | 11.27 | 7 | 7577 | 15832 |
| `/users/new` | 200 | 12.76 | 7 | 8999 | 18929 |
| `/vrps` | 200 | 14.37 | 8 | 9942 | 16212 |
| `/vrps/new` | 200 | 83.47 | 22 | 37032 | 25608 |
| `/vrps/approvals` | 200 | 12.53 | 8 | 6107 | 14839 |
| `/vrp-agreements` | 200 | 12.37 | 7 | 7786 | 14713 |
| `/afls` | 200 | 13.51 | 7 | 8102 | 15998 |
| `/target_mappings` | 200 | 21.55 | 11 | 12373 | 34600 |
| `/asa360-mapping` | 200 | 10.32 | 6 | 7200 | 14192 |
| `/target_mappings/list` | 200 | 8.99 | 10 | 6753 | 15831 |
| `/jj-mapped-farmers` | 200 | 9.79 | 6 | 6698 | 18190 |
| `/dashboard/vrp-list/assigned_farmers` | 302 | 1.82 | 0 | 1501 | 0 |
| `/dashboard/vrp-list/assigned_target` | 302 | 1.22 | 0 | 1429 | 0 |
| `/dashboard/vrp-list/mapped_villages` | 302 | 1.17 | 0 | 1447 | 0 |
| `/dashboard/vrp-list/pending_target` | 302 | 1.84 | 0 | 1458 | 0 |
| `/dashboard/vrp-list/achieved_target` | 302 | 1.35 | 0 | 1454 | 0 |
| `/dashboard/vrp-list/main_activities` | 302 | 1.19 | 0 | 1471 | 0 |
| `/dashboard/vrp-list/sub_activities` | 302 | 1.57 | 0 | 1429 | 0 |

## Verification and remaining production work

Matching/session/selector/billing/mapped-farmer/training-target checks: 33 tests, 170 assertions, no failures/errors. Login/agreement/deactivation: six tests, 52 assertions, no failures/errors, excluding two existing OTP mock-setup checks unrelated to these changes.

JavaScript checks: ten test files pass; the existing language switch test file fails because its fake document lacks getElementById. No JavaScript was changed in this round. This is not a fully green repository test suite. Earlier broad Ruby test failures and their original-controller reproductions are documented in the incident report.

On the production host, deploy the reviewed changes and obtain an active-request snapshot using `bash script/performance_runtime_snapshot.sh javika_production 6`. Verify actual Puma concurrency (the supplied startup said five threads despite the repository default of two), memory/CPU, DB wait events and Nginx errors. The logs do not distinguish CPU starvation, database IO, locking and query execution plans, so those causes must not be asserted as proven. The cold catalogue and large rendered datasets remain possible costs; this patch does not guarantee every page opens instantly.

Final combined cache, preload, matching, bill, staff-scope, duplicate-guard, dashboard and location-projection suite: **59 tests, 439 assertions, zero failures/errors**. Together with the separate six login/agreement/deactivation tests: **65 tests, 491 assertions**. `git diff --check` and Ruby syntax checks passed.
