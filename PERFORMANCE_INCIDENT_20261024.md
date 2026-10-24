# Slow requests and upstream timeouts — 24 October 2026

The attachment was correlated by request ID, not neighboring journal lines. Query strings, login parameters and client addresses are omitted. The Nginx errors subsequently supplied by the user confirm upstream response-header timeouts on billing, payment, training, other-target and VRP entry routes. They do not establish that every screenshot showing 502 has that exact cause: upstream timeout normally produces 504; connection failure/process termination needs its own error record.

## Findings and changes

- Location catalogue payload SELECT at `modules_controller.rb:15886` in the supplied version is the largest cumulative slow-query source: 29 logged executions, 1,306.970 seconds total, worst 359.668 seconds. This is cumulative concurrent query time, not incident wall time. Every new controller rebuilt the same shared catalogue. Cache the unchanged mapping under per-slug row counts and PostgreSQL row transaction versions (`xmin`). Every request checks that revision. Creates, updates (including imports that do not change `updated_at`), soft deletion and hard deletion invalidate it; unrelated module writes do not. The cache retains the configured Rails store and coalesces fills within a worker.
- Achievement candidates at line 12210 still loaded complete VRPs, including signature image data, despite other paths using lightweight associations. Apply the existing signature-free preloader to both candidate fallbacks and dashboard target summaries. Target sets, ordering, association values used by these screens, stored signatures, calculations and authorization predicates are unchanged.
- Journal startup shows 5 Puma threads. Repository production defaults and deploy.yml specify 2; environment overrides win. Verify the live systemd settings before assuming the repository setting is active. The shutdown timed out and SIGKILL occurred at 06:41 UTC (12:11 IST); memory peak was 1 GB. These observations support checking concurrency/memory pressure, but do not prove OOM or a particular database wait cause.
- Runtime snapshot script now defaults to the production DB name in database.yml, reports selected concurrency settings, memory/restart status, shutdown/startup evidence and recent Nginx errors with query strings redacted. It does not dump the full service environment.

## Local measurements

Dedicated PostgreSQL test database; 3,000 synthetic village rows, eight fresh controller instances including the first cache miss, all generated rows compared for equality, synthetic writes rolled back:

| Workload | Before | After |
| --- | ---: | ---: |
| Eight catalogue reads | 0.3844 s | 0.1924 s |
| Ruby allocations | 1,660,717 | 705,503 |
| SQL queries | 8 payload queries | 8 revision queries + 1 payload query |

This measures the catalogue helper only. It is not a production page latency claim. A cold catalogue still needs one full load and forms still transmit the catalogue; cache reuse reduces repeated database reconstruction. Production query plans, database waits, CPU/memory measurements and authenticated page timings are still required to determine remaining limits. No production deployment or restart was performed.

## Every completed route in the attachment

Times below are Rails completion durations. A Rails 200 after the proxy gives up does not mean the browser received a page. Incomplete requests cannot be assigned a response duration.

| Route | Requests | Min seconds | Max seconds | Rails status |
| --- | ---: | ---: | ---: | --- |
| `GET /modules/jeevika-jankar-bill-process` | 2 | 245.799 | 370.788 | 200 |
| `GET /modules/other-target` | 9 | 15.874 | 364.855 | 200 |
| `GET /modules/jeevika-jankar-payment-list` | 5 | 58.981 | 330.131 | 200 |
| `GET /modules/jeevika-jankar-bill-list` | 4 | 41.194 | 326.744 | 200 |
| `GET /modules/other-target-with-farmer` | 15 | 5.622 | 170.927 | 200 |
| `GET /modules/lg-directory-list` | 4 | 25.592 | 110.854 | 200 |
| `GET /modules/training-form-list` | 13 | 0.325 | 100.892 | 200 |
| `GET /modules/jeevika-jankar-payment-list-detail` | 2 | 1.426 | 96.537 | 200 |
| `GET /modules/other-target-list` | 11 | 0.092 | 75.102 | 200 |
| `GET /dashboard` | 12 | 8.778 | 72.190 | 200 |
| `GET /target_mappings/list` | 3 | 7.038 | 71.953 | 200 |
| `GET /modules/village-master` | 1 | 59.679 | 59.679 | 200 |
| `GET /modules/district-master` | 2 | 15.209 | 46.178 | 200 |
| `GET /modules/block-master` | 1 | 45.396 | 45.396 | 200 |
| `GET /users/new` | 1 | 39.800 | 39.800 | 200 |
| `GET /modules/gram-panchayat-master` | 1 | 36.086 | 36.086 | 200 |
| `GET /vrps/new` | 1 | 27.961 | 27.961 | 200 |
| `GET /dashboard/vrp-list/assigned_farmers` | 2 | 11.356 | 26.140 | 200 |
| `GET /dashboard/vrp-list/achieved_target` | 3 | 15.497 | 25.809 | 200 |
| `GET /target_mappings` | 4 | 0.249 | 25.296 | 200 |
| `Request started before attachment` | 4 | 11.108 | 23.908 | 200 |
| `GET /dashboard/vrp-list/mapped_villages` | 1 | 23.445 | 23.445 | 200 |
| `GET /dashboard/vrp-list/assigned_target` | 1 | 23.404 | 23.404 | 200 |
| `GET /modules/training-form` | 12 | 2.517 | 21.997 | 200 |
| `GET /dashboard/vrp-list/sub_activities` | 3 | 12.717 | 20.745 | 200 |
| `GET /jj-mapped-farmers` | 5 | 0.090 | 20.450 | 200 |
| `GET /modules/training-form/training_target_farmers` | 1 | 18.462 | 18.462 | 200 |
| `GET /modules/other-target-with-farmer-list` | 8 | 0.071 | 16.662 | 200 |
| `GET /dashboard/vrp-list/pending_target` | 2 | 15.919 | 16.056 | 200 |
| `GET /vrps` | 1 | 9.594 | 9.594 | 200 |
| `GET /modules/other-target-with-farmer/seed_target_farmers` | 1 | 9.337 | 9.337 | 200 |
| `GET /modules/office-list` | 1 | 8.645 | 8.645 | 200 |
| `GET /modules/jeevika-jankar-completed-payment-list` | 6 | 0.047 | 6.476 | 200 |
| `GET /modules/office-category-add` | 1 | 6.070 | 6.070 | 200 |
| `POST /login` | 11 | 0.005 | 6.027 | 302 |
| `POST /modules/training-form/records` | 1 | 5.459 | 5.459 | 302 |
| `GET /modules/parent-office-add` | 1 | 4.803 | 4.803 | 200 |
| `GET /vrp-agreements` | 3 | 0.086 | 4.709 | 200 |
| `GET /modules/access-control-list` | 1 | 4.496 | 4.496 | 200 |
| `GET /modules/add-activity-group` | 1 | 4.066 | 4.066 | 200 |
| `GET /vrps/approvals` | 1 | 3.675 | 3.675 | 200 |
| `GET /modules/jeevika-jankar-observation-list` | 2 | 0.129 | 2.831 | 200 |
| `GET /vrp-agreement` | 1 | 2.605 | 2.605 | 200 |
| `GET /modules/stakeholder-master` | 1 | 2.526 | 2.526 | 200 |
| `GET /modules/user-hierarchy-list` | 1 | 2.180 | 2.180 | 200 |
| `GET /modules/jeevika-jankar-transfer-list` | 1 | 2.107 | 2.107 | 200 |
| `GET /` | 7 | 0.004 | 2.022 | 200, 302 |
| `GET /modules/office-mapping-add` | 1 | 1.167 | 1.167 | 200 |
| `GET /asa360-mapping` | 1 | 0.905 | 0.905 | 200 |
| `GET /modules/approval-list` | 1 | 0.351 | 0.351 | 200 |
| `GET /modules/project-master` | 1 | 0.227 | 0.227 | 200 |
| `GET /modules/jeevika-jankar-transfer` | 1 | 0.212 | 0.212 | 200 |
| `GET /modules/vrp-activity-list` | 1 | 0.199 | 0.199 | 200 |
| `GET /modules/user-hierarchy-mapping` | 1 | 0.166 | 0.166 | 200 |
| `GET /modules/add-vrp-activity` | 1 | 0.158 | 0.158 | 200 |
| `GET /modules/role-name` | 1 | 0.126 | 0.126 | 200 |
| `GET /modules/access-control` | 1 | 0.112 | 0.112 | 200 |
| `GET /users` | 1 | 0.112 | 0.112 | 200 |
| `GET /modules/stakeholder-role` | 1 | 0.105 | 0.105 | 200 |
| `GET /dashboard/farmer-participation-report` | 1 | 0.096 | 0.096 | 403 |
| `GET /afls` | 1 | 0.084 | 0.084 | 200 |
| `GET /modules/approval-master` | 1 | 0.068 | 0.068 | 200 |
| `GET /modules/activity-group-list` | 1 | 0.064 | 0.064 | 200 |
| `GET /modules/state-master` | 2 | 0.047 | 0.055 | 200 |
| `GET /login` | 11 | 0.009 | 0.052 | 200 |
| `GET /target_mappings/saved_farmers` | 1 | 0.027 | 0.027 | 200 |
| `GET /logout` | 1 | 0.005 | 0.005 | 302 |

## Largest cumulative logged SQL sources

Source line numbers refer to the supplied production log/version. These are thresholded slow SQL events, not all queries.

| Source | Events | Cumulative seconds | Worst seconds |
| --- | ---: | ---: | ---: |
| `app/controllers/modules_controller.rb:15886` | 29 | 1306.970 | 359.668 |
| `app/controllers/modules_controller.rb:9755` | 29 | 473.830 | 81.958 |
| `app/controllers/modules_controller.rb:12210` | 28 | 234.509 | 79.507 |
| `app/controllers/modules_controller.rb:8920` | 5 | 148.417 | 62.550 |
| `app/controllers/modules_controller.rb:10277` | 4 | 141.630 | 68.514 |
| `app/controllers/modules_controller.rb:2880` | 16 | 132.937 | 49.937 |
| `app/helpers/application_helper.rb:416` | 52 | 83.305 | 4.895 |
| `app/controllers/modules_controller.rb:11640` | 4 | 59.695 | 20.086 |
| `app/controllers/target_mappings_controller.rb:1937` | 4 | 59.153 | 50.152 |
| `app/controllers/modules_controller.rb:9496` | 46 | 54.378 | 2.438 |
| `app/helpers/application_helper.rb:801` | 39 | 47.309 | 3.313 |
| `app/controllers/modules_controller.rb:9129` | 4 | 46.850 | 23.703 |
| `app/controllers/dashboard_reports_controller.rb:2384` | 18 | 41.443 | 10.771 |
| `app/controllers/modules_controller.rb:9503` | 6 | 40.593 | 15.713 |
| `app/helpers/application_helper.rb:810` | 38 | 39.909 | 2.447 |

## Validation

Focused suite: 54 tests, 380 assertions, no failures/errors. It covers cache reuse and mutation isolation across requests, invalidation on create/edit/soft delete/hard delete, both achievement candidate fallback preloads, bill totals/payment projection, staff scoping, duplicate bill rules, dashboard controller checks and location projection equivalence.

The initial wider performance run had three failures and one error; all four reproduced after loading the original HEAD controller. The wider VRP dashboard suite had 12 failures; all 12 also reproduced on the original HEAD controller (21 tests). These existing failures include stale UI assertions, authentication/target setup expectations, and a not-null test fixture error; the full repository suite is not green. No business rules were changed to make these tests pass.

Ruby syntax, shell syntax and `git diff --check` pass.

For live diagnostics, run `bash script/performance_runtime_snapshot.sh javika_production 6` on the production host while opening one affected page. The script reads service state, process/memory statistics, Nginx errors and database waits. Use the database argument if the deployment overrides the configured database name. Inspect both active Puma settings and waits before changing worker counts or database indexes. This workspace has no supplied production SSH connection; the attached logs are production evidence, not direct live-server access.
