# JJ request performance review — 2026-10-05, latest 10:34 UTC log

Requests were correlated by request ID, not adjacent journal lines. Route ranges include completed redirects as well as successful page renders. Times are observed request durations; ActiveRecord includes cached-query processing and can overlap GC time. GC must not be added to the other timings. Query strings and authentication parameters are omitted.

## Every completed route in the attachment

| Route | Requests | Min–max seconds | Worst request DB seconds | Worst request queries / cached |
| --- | ---: | ---: | ---: | ---: |
| `GET /modules/village-master` | 2 | 51.033–84.748 | 55.116 | 11 / 0 |
| `GET /modules/training-form` | 12 | 1.588–54.236 | 5.814 | 111 / 87 |
| `GET /modules/jeevika-jankar-bill-list` | 6 | 5.094–49.117 | 40.943 | 259 / 66 |
| `GET /modules/district-master` | 3 | 9.439–44.048 | 39.373 | 7 / 0 |
| `GET /modules/other-target` | 10 | 5.210–40.358 | 35.024 | 23 / 3 |
| `GET /dashboard` | 18 | 0.002–40.213 | 36.469 | 51 / 3 |
| `GET /modules/gram-panchayat-master` | 2 | 31.373–32.554 | 17.103 | 9 / 0 |
| `GET /modules/lg-directory-list` | 2 | 8.657–30.144 | 18.961 | 11 / 0 |
| `GET /modules/training-form-list/export.zip` | 1 | 29.789–29.789 | 4.001 | 12 / 0 |
| `GET /vrps` | 4 | 0.337–28.907 | 23.311 | 2916 / 2893 |
| `GET /vrps/new` | 4 | 14.428–25.183 | 15.708 | 33 / 5 |
| `GET /modules/training-form-list` | 21 | 0.102–23.977 | 17.598 | 17 / 2 |
| `GET /vrps/approvals` | 5 | 2.928–13.260 | 8.366 | 2899 / 2887 |
| `GET /dashboard/vrp-list/assigned_target` | 1 | 11.634–11.634 | 8.652 | 42 / 3 |
| `GET /jj-mapped-farmers` | 4 | 0.113–10.521 | 0.429 | 7 / 0 |
| `GET /dashboard/vrp-list/sub_activities` | 1 | 9.513–9.513 | 6.660 | 42 / 3 |
| `GET /dashboard/vrp-list/mapped_villages` | 1 | 8.872–8.872 | 5.241 | 43 / 3 |
| `GET /dashboard/vrp-list/assigned_farmers` | 1 | 8.527–8.527 | 5.501 | 43 / 3 |
| `GET /dashboard/vrp-list/main_activities` | 1 | 8.035–8.035 | 4.345 | 42 / 3 |
| `GET /target_mappings/vrp_mappings` | 12 | 0.031–6.623 | 1.485 | 11 / 0 |
| `GET /target_mappings` | 12 | 0.232–6.361 | 6.144 | 20 / 4 |
| `GET /vrp-agreements` | 5 | 0.355–6.317 | 6.272 | 10 / 0 |
| `GET /modules/jeevika-jankar-payment-list` | 7 | 0.106–6.149 | 5.998 | 9 / 1 |
| `POST /modules/training-form/records` | 3 | 1.424–6.130 | 5.867 | 16 / 0 |
| `GET /modules/jeevika-jankar-completed-payment-list` | 6 | 0.040–4.530 | 4.505 | 10 / 1 |
| `GET /modules/month-master` | 1 | 3.868–3.868 | 3.838 | 7 / 0 |
| `GET /target_mappings/list` | 4 | 0.669–3.124 | 2.743 | 11 / 1 |
| `GET /modules/jeevika-jankar-observation-list` | 4 | 0.390–2.921 | 2.859 | 7 / 0 |
| `POST /login` | 7 | 0.006–2.485 | 2.479 | 1 / 0 |
| `GET /modules/office-list` | 1 | 2.036–2.036 | 0.004 | 5 / 0 |
| `GET /modules/add-vrp-type` | 2 | 0.083–1.796 | 1.778 | 4 / 0 |
| `GET /target_mappings/village_farmers` | 3 | 0.692–1.632 | 0.000 | 0 / 0 |
| `GET /users/new` | 2 | 1.034–1.230 | 0.036 | 8 / 0 |
| `GET /modules/user-hierarchy-mapping` | 3 | 0.065–1.176 | 1.137 | 7 / 0 |
| `GET /modules/add-activity-group` | 1 | 1.088–1.088 | 1.046 | 10 / 0 |
| `GET /modules/other-target-list` | 6 | 0.058–0.978 | 0.850 | 16 / 3 |
| `POST /target_mappings` | 2 | 0.220–0.832 | 0.692 | 26 / 13 |
| `GET /modules/user-hierarchy-list` | 2 | 0.733–0.823 | 0.061 | 7 / 0 |
| `GET /modules/access-control` | 1 | 0.807–0.807 | 0.734 | 13 / 6 |
| `GET /modules/jeevika-jankar-bill-process` | 2 | 0.541–0.724 | 0.578 | 10 / 1 |
| `GET /modules/parent-office-add` | 1 | 0.652–0.652 | 0.621 | 10 / 1 |
| `GET /modules/office-mapping-add` | 1 | 0.460–0.460 | 0.359 | 9 / 0 |
| `GET /modules/office-category-add` | 1 | 0.366–0.366 | 0.321 | 8 / 0 |
| `GET /modules/jeevika-jankar-payment-list-detail` | 2 | 0.060–0.255 | 0.201 | 6 / 0 |
| `GET /login` | 10 | 0.009–0.232 | 0.221 | 3 / 0 |
| `GET /modules/approval-list` | 2 | 0.099–0.232 | 0.112 | 5 / 0 |
| `GET /modules/role-name` | 1 | 0.113–0.113 | 0.043 | 11 / 0 |
| `GET /modules/access-control-list` | 1 | 0.104–0.104 | 0.074 | 5 / 0 |
| `GET /logout` | 5 | 0.003–0.101 | 0.000 | 0 / 0 |
| `GET /afls` | 1 | 0.090–0.090 | 0.012 | 7 / 0 |
| `GET /modules/approval-master` | 3 | 0.029–0.090 | 0.037 | 6 / 0 |
| `GET /modules/project-master` | 1 | 0.084–0.084 | 0.026 | 5 / 0 |
| `GET /modules/state-master` | 1 | 0.073–0.073 | 0.039 | 5 / 0 |
| `GET /modules/stakeholder-role` | 1 | 0.056–0.056 | 0.009 | 7 / 0 |
| `GET /modules/activity-group-list` | 1 | 0.054–0.054 | 0.035 | 5 / 0 |
| `POST /modules/other-target/records` | 1 | 0.052–0.052 | 0.015 | 11 / 0 |
| `GET /users` | 1 | 0.045–0.045 | 0.005 | 6 / 0 |
| `GET /modules/add-vrp-activity` | 1 | 0.042–0.042 | 0.006 | 6 / 0 |
| `GET /asa360-mapping` | 1 | 0.030–0.030 | 0.008 | 5 / 0 |
| `GET /forgot-password` | 1 | 0.028–0.028 | 0.008 | 3 / 0 |
| `GET /modules/vrp-activity-list` | 1 | 0.026–0.026 | 0.005 | 5 / 0 |
| `GET /modules/stakeholder-master` | 1 | 0.022–0.022 | 0.004 | 5 / 0 |
| `GET /` | 1 | 0.002–0.002 | 0.000 | 0 / 0 |

## Implemented changes

- VRP approver labels: resolve current database and legacy user once per request, preserving exact label expansion and matching rules.
- Training hierarchy: load active ordered records once and index the first matching record per normalized member. Preserve newest-match precedence, specialist traversal and cycle fallback.
- Master/list field display: reuse static aliases, field sources and normalized field keys per request. Values remain read from each record, including arrays and numeric values.
- Bill target loading: evaluate empty-scope checks on loaded ordered targets. Retain restricted-scope and numeric-month fallbacks. A normal matching bill scope uses one target SELECT instead of extra existence SELECTs.

## Local before/after measurements

Same local development data, separate Rails runner processes, no application writes. Result SHA-256 hashes matched for every workload. Timing is illustrative and is not a production request SLA.

| Workload | Before | After | Queries before → after | Allocations before → after |
| --- | ---: | ---: | ---: | ---: |
| vrp_index | 0.1160s | 0.1366s | 8 → 8 | 89,456 → 108,797 |
| village_table_cells_5_passes | 0.8786s | 0.3374s | 2 → 2 | 7,296,452 → 1,313,265 |
| training_hierarchy_map | 0.0137s | 0.0024s | 16 → 1 | 32,042 → 2,441 |
| approver_checks_1000 | 1.0106s | 0.0046s | 2000 → 2 | 1,235,810 → 15,653 |

The local VRP index dataset did not exercise the production repeated-approver workload and its isolated timing did not improve. The 1,000-check workload specifically exercises that path with Rails query caching enabled.

## Production evidence still needed

The supplied INFO logs do not contain SQL statements, query plans, DB wait events, or proof that the concurrent index migrations were applied successfully. An 84.7s village request with 11 queries cannot be attributed to N+1 alone. Do not add duplicate indexes or change pagination from these aggregate numbers.

`PERFORMANCE_DIAGNOSTICS.sql` now also reports actual index definitions, valid/ready flags, migration versions and table sizes. Run it while a slow request is active. It uses a read-only transaction and a 5-second statement timeout. No production restart, deployment, migration, index creation, or database modification was performed in this round.

## Validation

Targeted performance, VRP, billing, hierarchy and dashboard API suite: 45 tests, 513 assertions, zero failures/errors. Login/session and training-list suite: 19 tests, 97 assertions, zero failures/errors after excluding two pre-existing OTP tests that raise `NameError: uninitialized constant Minitest::Mock`. Those OTP test errors were observed in the unfiltered run; their controller and tests were not changed. Read-only diagnostics SQL passed on the local development database. `git diff --check` passed.
