# 11 November 2026: supplied slow-log review and fixes

Follow-up: `PERFORMANCE_EDIT_RESCAN_20261111.md` adds master edit pagination, table-only frame rendering and GP dropdown projection; it supersedes this first pass's Village edit status.

Baseline: `6e1407e63f00e7c606630f1dc68d8661c7132943`. Source: the supplied November 11 journal attachment. These are historical production timings, not post-patch measurements. All 1,045 supplied lines were processed by request ID: 218 IDs, 214 completions, 47 over 1,000 ms, and four IDs without a completion in the supplied excerpt. Completion statuses: 165 × 200, 39 × 302, eight × 303 and two × 304. No completed 4xx/5xx response appears. One unmatched `/admin/config.php` scanner request has a RoutingError; adding a business route for it would not speed up a page.

## Changes made in this pass

- LG Directory show skips the unused full ModuleRecord list. Its dedicated projected directory remains the data source, including inactive rows, aliases, ordering, filtering, selection tokens, bulk controls and export. The log shows the removed duplicate stage taking 4,203.7 ms and allocating 1,968,526 objects before the separate directory build even starts.
- Office List skips its unused ModuleRecord list; its existing external API source and rows remain unchanged.
- Admin target lists skip the JJ visibility preload/filter because the existing predicate always returns true for admins. Staff/JJ permission paths are unchanged; no cross-request permission cache was added.
- LG bulk matching uses a Set of the existing normalized row keys instead of scanning all selected keys per candidate. Duplicate rows across master sources still match; result order remains the database's existing order. Empty selection returns no rows without querying the entire catalogue.

## Measured comparison

`script/benchmark_directory_reads.rb` compares against HEAD with 15,136 generated directory rows in an isolated test database, all rolled back. Full returned directory arrays and bulk matched IDs/order are compared for equality.

| Workload | Before ms | After ms | Allocations before | Allocations after |
|---|---:|---:|---:|---:|
| Cold directory data preparation | 1,424.71 | 532.92 | 2,913,366 | 1,211,696 |
| Bulk matching 1,000 selected rows | 432.76 | 348.37 | 1,167,165 | 1,157,160 |

Single local synthetic runs; excludes HTTP rendering, network transfer and browser parsing. This is not a production speed claim or a 5 ms page guarantee.

## Verification and behavior scan

Combined suite: **89 tests, 1,763 assertions, zero failures/errors/skips**. Covers new directory behavior/query checks, rendered filters/checkboxes/status/escaping/bulk/export controls, admin training ordering and approval snapshots, training routing errors, staff cluster visibility, target read behavior, user options, cache escaping/invalidation, log hotspots and farmer-page rendering. Benchmark compares complete directory and selection outputs against baseline. Ruby syntax and diff checks pass. No schema or business-write change is included. Full application suite and production browser timings were not run.

## Remaining bottlenecks: not claimed resolved

- Village edit (18,267 ms), Block list (8,467 ms), User new/edit (7,293/7,515 ms): existing escaped-location caches, projected reads and master pagination were already present at the baseline. This pass validates their existing behavior but does not establish that their production cache hits are healthy. Cold location projections still have 1,411–1,711 ms SQL markers; large location attributes/dropdowns still incur transfer/browser work. Profiling production-sized queries and cold/warm HTTP responses remains required.
- LG Directory: duplicate loading is fixed, but the cold directory build and rendering all directory rows remain costs. Existing client-side selection/pagination is preserved.
- External JJ catalogue: 7,507.7 ms wall time versus 92.4 ms process CPU. Office API: 3,252.6 ms wall time versus 36.1 ms process CPU. Local Ruby changes do not eliminate upstream waits. Existing cache/error freshness behavior is preserved.
- Training visibility (3,874.2 ms; 2,447,380 allocations) was a non-admin read, so the new admin bypass does not claim to fix it. Existing normalization/indexing remains; production profiling of the staff scope is still needed.
- Training list SQL (1,335 ms), scalar form-option SQL (up to 2,535.7 ms), bill/payment rendering, dashboard aggregates, JJ approval/index CPU and target mapping payloads remain measured latency candidates. The attachment does not contain production EXPLAIN plans or browser traces needed to attribute all of those costs precisely.
- No deployment or server restart was performed. Fresh production logs after deployment are required to measure actual gains and choose the next bottleneck. No universal 5 ms assertion is justified.

## Every completed request, slowest first

Signed storage paths are redacted. Query strings, IP addresses and form contents are omitted. SQL/GC durations overlap wall time and must not be added together.

| Completion line | Request | Status | Total ms | Views ms | SQL ms | GC ms |
|---:|---|---:|---:|---:|---:|---:|
| 542 | `/modules/village-master/records/143887/edit` | 200 | 18267.0 | 15260.6 | 2027.0 | 3361.5 |
| 442 | `/modules/lg-directory-list` | 200 | 12049.0 | 468.1 | 1830.2 | 2656.0 |
| 622 | `/modules/block-master` | 200 | 8467.0 | 6503.6 | 1930.6 | 1820.9 |
| 854 | `/jj-mapped-farmers` | 200 | 7539.0 | 20.4 | 102.8 | 10.2 |
| 777 | `/users/115/edit` | 200 | 7515.0 | 433.9 | 269.1 | 1627.6 |
| 747 | `/users/new` | 200 | 7293.0 | 806.0 | 243.3 | 1773.7 |
| 840 | `/target_mappings` | 200 | 5403.0 | 1686.8 | 214.1 | 496.9 |
| 640 | `/modules/village-master` | 200 | 5106.0 | 400.0 | 404.9 | 622.5 |
| 913 | `/modules/jeevika-jankar-bill-list` | 200 | 4717.0 | 4043.5 | 523.0 | 792.5 |
| 491 | `/modules/lg-directory-list/bulk_update` | 302 | 4247.0 | — | 131.4 | 1141.0 |
| 1019 | `/modules/training-form-list` | 200 | 3992.0 | 11.4 | 110.1 | 331.4 |
| 86 | `/vrps` | 200 | 3853.0 | 19.6 | 109.3 | 1034.6 |
| 1004 | `/vrps` | 200 | 3763.0 | 14.9 | 54.1 | 837.5 |
| 382 | `/vrps` | 200 | 3574.0 | 21.9 | 85.6 | 815.7 |
| 708 | `/modules/office-list` | 200 | 3314.0 | 20.3 | 4.7 | 9.2 |
| 918 | `/modules/jeevika-jankar-bill-process/records/183429/edit` | 200 | 3291.0 | 13.7 | 606.3 | 357.6 |
| 809 | `/vrps/approvals` | 200 | 3106.0 | 30.8 | 31.2 | 824.0 |
| 723 | `/modules/add-activity-group` | 200 | 2744.0 | 39.6 | 2700.7 | 0.4 |
| 929 | `/modules/jeevika-jankar-payment-list` | 200 | 2624.0 | 1330.9 | 413.3 | 448.4 |
| 153 | `/modules/jeevika-jankar-bill-list` | 200 | 2502.0 | 944.6 | 210.6 | 527.0 |
| 34 | `/dashboard` | 200 | 2215.0 | 63.0 | 309.2 | 494.9 |
| 643 | `/modules/gram-panchayat-master` | 200 | 2065.0 | 258.6 | 447.6 | 361.1 |
| 155 | `/modules/jeevika-jankar-bill-list/records/182709/download_bill` | 200 | 1887.0 | 1465.1 | 172.7 | 578.9 |
| 860 | `/modules/training-form` | 200 | 1849.0 | 435.9 | 1409.8 | 41.0 |
| 173 | `/modules/jeevika-jankar-bill-list` | 200 | 1802.0 | 884.2 | 157.1 | 236.0 |
| 979 | `/dashboard` | 200 | 1795.0 | 36.1 | 268.1 | 301.1 |
| 75 | `/modules/jeevika-jankar-bill-list/records/182729/download_bill` | 200 | 1753.0 | 1420.8 | 171.0 | 193.9 |
| 872 | `/modules/training-form/records/181941/edit` | 200 | 1728.0 | 1530.2 | 194.1 | 163.1 |
| 175 | `/modules/jeevika-jankar-bill-list/records/182706/download_bill` | 200 | 1640.0 | 1313.5 | 142.0 | 413.4 |
| 867 | `/modules/training-form-list` | 200 | 1609.0 | 228.1 | 1348.1 | 11.7 |
| 849 | `/target_mappings/list` | 200 | 1526.0 | 1134.6 | 50.0 | 340.1 |
| 110 | `/modules/jeevika-jankar-bill-list/records/182710/download_bill` | 200 | 1505.0 | 1184.1 | 182.0 | 432.6 |
| 23 | `/modules/jeevika-jankar-bill-list/records/183094/download_bill` | 200 | 1498.0 | 1050.6 | 222.4 | 404.4 |
| 3 | `start absent in excerpt` | 200 | 1430.0 | 1089.2 | 160.8 | 76.4 |
| 936 | `/modules/jeevika-jankar-payment-list-detail` | 200 | 1390.0 | 188.7 | 483.0 | 59.9 |
| 387 | `/modules/jeevika-jankar-bill-list/records/182547/download_bill` | 200 | 1365.0 | 1029.8 | 179.7 | 348.2 |
| 303 | `/modules/jeevika-jankar-bill-list/records/182647/download_bill` | 200 | 1364.0 | 1006.1 | 148.2 | 450.7 |
| 96 | `/modules/jeevika-jankar-bill-list/records/182728/download_bill` | 200 | 1330.0 | 992.4 | 183.3 | 112.9 |
| 414 | `/modules/jeevika-jankar-bill-list/records/182450/download_bill` | 200 | 1309.0 | 984.5 | 136.8 | 148.1 |
| 648 | `/modules/jeevika-jankar-bill-list/records/183403/download_bill` | 200 | 1262.0 | 1081.7 | 150.9 | 339.0 |
| 289 | `/modules/jeevika-jankar-bill-list/records/182684/download_bill` | 200 | 1136.0 | 810.4 | 190.5 | 169.1 |
| 221 | `/modules/jeevika-jankar-bill-list/records/182700/download_bill` | 200 | 1109.0 | 794.2 | 179.6 | 216.5 |
| 430 | `/modules/jeevika-jankar-bill-list/records/181841/download_bill` | 200 | 1075.0 | 750.3 | 143.7 | 99.6 |
| 627 | `/modules/month-master` | 200 | 1075.0 | 29.7 | 1042.5 | 0.0 |
| 359 | `/modules/jeevika-jankar-bill-list/records/182636/download_bill` | 200 | 1063.0 | 717.7 | 185.5 | 123.9 |
| 331 | `/modules/jeevika-jankar-bill-list/records/182638/download_bill` | 200 | 1059.0 | 728.5 | 171.1 | 129.8 |
| 39 | `/modules/jeevika-jankar-bill-list/records/183093/download_bill` | 200 | 1030.0 | 709.1 | 146.0 | 162.0 |
| 235 | `/modules/jeevika-jankar-bill-list/records/183435/download_bill` | 200 | 988.0 | 812.3 | 142.6 | 69.5 |
| 458 | `/modules/jeevika-jankar-bill-list` | 200 | 987.0 | 333.5 | 462.2 | 94.9 |
| 1029 | `/modules/jeevika-jankar-bill-list` | 200 | 964.0 | 11.4 | 29.1 | 0.0 |
| 531 | `/modules/jeevika-jankar-bill-list/records/183429/download_bill` | 200 | 936.0 | 754.5 | 127.4 | 322.9 |
| 192 | `/dashboard` | 200 | 918.0 | 36.1 | 565.4 | 68.9 |
| 197 | `/modules/jeevika-jankar-bill-list/records/182702/download_bill` | 200 | 871.0 | 501.6 | 188.2 | 71.6 |
| 602 | `/modules/jeevika-jankar-bill-list/records/183426/download_bill` | 200 | 864.0 | 738.0 | 83.6 | 262.7 |
| 468 | `/modules/jeevika-jankar-bill-list/records/183430/download_bill` | 200 | 835.0 | 622.5 | 146.4 | 240.5 |
| 987 | `/dashboard` | 200 | 815.0 | 36.5 | 536.6 | 13.8 |
| 400 | `/modules/jeevika-jankar-bill-process/jeevika_jankar_bill_target_rows` | 200 | 807.0 | 0.2 | 224.8 | 260.1 |
| 91 | `/modules/jeevika-jankar-bill-list` | 200 | 761.0 | 547.0 | 173.1 | 38.4 |
| 262 | `/dashboard` | 200 | 689.0 | 32.5 | 554.4 | 6.6 |
| 408 | `/modules/jeevika-jankar-bill-list` | 200 | 679.0 | 353.9 | 179.5 | 47.3 |
| 1037 | `/dashboard` | 200 | 675.0 | 38.5 | 416.0 | 26.7 |
| 995 | `/vrps/new` | 200 | 669.0 | 283.5 | 84.3 | 233.6 |
| 547 | `/modules/jeevika-jankar-bill-list` | 200 | 661.0 | 350.2 | 110.5 | 57.0 |
| 552 | `/modules/jeevika-jankar-bill-list` | 200 | 660.0 | 396.2 | 109.8 | 7.7 |
| 62 | `/vrps` | 302 | 644.0 | — | 272.8 | 62.3 |
| 828 | `/vrp-agreements` | 200 | 642.0 | 102.9 | 480.4 | 0.0 |
| 597 | `/modules/jeevika-jankar-bill-list` | 200 | 638.0 | 431.1 | 125.9 | 232.7 |
| 1023 | `/dashboard` | 200 | 609.0 | 29.3 | 399.0 | 0.0 |
| 344 | `/modules/jeevika-jankar-bill-process/jeevika_jankar_bill_target_rows` | 200 | 603.0 | 0.3 | 244.2 | 75.8 |
| 284 | `/dashboard` | 200 | 595.0 | 24.9 | 470.7 | 6.2 |
| 667 | `/modules/district-master` | 200 | 576.0 | 430.7 | 126.5 | 353.5 |
| 485 | `/modules/jeevika-jankar-bill-list` | 200 | 552.0 | 121.9 | 235.8 | 54.3 |
| 801 | `/vrps/new` | 200 | 549.0 | 173.7 | 119.1 | 123.1 |
| 887 | `/modules/other-target-with-farmer` | 200 | 544.0 | 412.5 | 93.7 | 94.0 |
| 991 | `/users/new` | 200 | 541.0 | 432.2 | 72.2 | 124.4 |
| 897 | `/modules/other-target-with-farmer/records/181315/edit` | 200 | 515.0 | 358.0 | 111.4 | 78.5 |
| 882 | `/modules/other-target-list` | 200 | 493.0 | 373.6 | 16.9 | 179.2 |
| 463 | `/modules/jeevika-jankar-bill-list` | 200 | 469.0 | 300.8 | 142.5 | 97.6 |
| 702 | `/modules/office-mapping-add` | 200 | 455.0 | 50.6 | 397.3 | 2.8 |
| 901 | `/modules/other-target-with-farmer/seed_target_farmers` | 200 | 429.0 | 0.6 | 67.0 | 9.8 |
| 321 | `/dashboard` | 200 | 428.0 | 23.3 | 285.9 | 24.1 |
| 616 | `/modules/district-master` | 200 | 396.0 | 229.3 | 147.0 | 170.1 |
| 326 | `/modules/jeevika-jankar-bill-process` | 200 | 395.0 | 12.0 | 316.7 | 12.4 |
| 1042 | `/api/v1/farmer/login/otp/send` | 200 | 395.0 | 0.2 | 20.4 | 0.0 |
| 877 | `/modules/other-target` | 200 | 375.0 | 209.5 | 108.9 | 57.8 |
| 906 | `/modules/jeevika-jankar-bill-process` | 200 | 369.0 | 11.6 | 324.8 | 0.0 |
| 355 | `/modules/jeevika-jankar-bill-process` | 200 | 363.0 | 12.5 | 286.4 | 17.8 |
| 144 | `/modules/jeevika-jankar-bill-list/records/183426/send_for_approval` | 303 | 348.0 | — | 286.1 | 18.6 |
| 142 | `/modules/jeevika-jankar-bill-list/records/183429/send_for_approval` | 303 | 335.0 | — | 337.0 | 0.0 |
| 662 | `/modules/block-master` | 200 | 335.0 | 139.6 | 185.6 | 57.7 |
| 634 | `/modules/jeevika-jankar-bill-list/records/183426/approve_bill` | 200 | 326.0 | 0.2 | 43.7 | 176.0 |
| 805 | `/vrps` | 200 | 297.0 | 32.3 | 41.9 | 0.0 |
| 692 | `/modules/parent-office-add` | 200 | 287.0 | 31.4 | 250.5 | 3.0 |
| 697 | `/modules/office-category-add` | 200 | 280.0 | 31.1 | 245.1 | 0.2 |
| 687 | `/modules/role-name` | 200 | 278.0 | 43.5 | 229.1 | 3.6 |
| 446 | `/modules/jeevika-jankar-bill-list/records/183435/approve_bill` | 200 | 274.0 | 0.2 | 98.1 | 67.8 |
| 140 | `/modules/jeevika-jankar-bill-list/records/183403/send_for_approval` | 303 | 212.0 | — | 104.6 | 0.0 |
| 782 | `/modules/access-control` | 200 | 210.0 | 61.4 | 146.9 | 0.0 |
| 1008 | `/target_mappings` | 200 | 210.0 | 65.1 | 36.2 | 23.7 |
| 682 | `/modules/stakeholder-role` | 200 | 209.0 | 37.0 | 167.2 | 0.2 |
| 757 | `/modules/user-hierarchy-list` | 200 | 209.0 | 193.5 | 10.9 | 9.6 |
| 138 | `/modules/jeevika-jankar-bill-list/records/183430/send_for_approval` | 303 | 191.0 | — | 80.2 | 5.3 |
| 733 | `/modules/add-vrp-activity` | 200 | 169.0 | 42.8 | 119.9 | 1.2 |
| 832 | `/modules/jeevika-jankar-bill-list/records/183403/approve_bill` | 200 | 169.0 | 0.2 | 63.3 | 0.0 |
| 892 | `/modules/other-target-with-farmer-list` | 200 | 169.0 | 115.3 | 12.5 | 11.7 |
| 489 | `/modules/jeevika-jankar-bill-list/records/183430/approve_bill` | 200 | 158.0 | 0.2 | 47.8 | 0.0 |
| 451 | `/modules/jeevika-jankar-bill-list/records/183428/send_for_approval` | 303 | 154.0 | — | 43.1 | 0.0 |
| 124 | `/modules/jeevika-jankar-bill-list/records/183435/send_for_approval` | 303 | 150.0 | — | 26.9 | 8.4 |
| 592 | `/modules/jeevika-jankar-bill-list/records/183429/approve_bill` | 200 | 147.0 | 0.2 | 32.1 | 0.0 |
| 357 | `/modules/jeevika-jankar-bill-process` | 200 | 130.0 | 13.7 | 28.7 | 14.4 |
| 762 | `/modules/jeevika-jankar-transfer` | 200 | 130.0 | 57.2 | 71.5 | 1.2 |
| 824 | `/modules/approval-list` | 200 | 120.0 | 92.1 | 6.5 | 17.8 |
| 378 | `/vrps/334/send_for_approval` | 303 | 115.0 | — | 44.8 | 1.8 |
| 941 | `/modules/jeevika-jankar-completed-payment-list` | 200 | 113.0 | 62.1 | 36.3 | 3.1 |
| 1002 | `/modules/approval-list` | 200 | 112.0 | 79.8 | 11.9 | 0.0 |
| 588 | `/modules/state-master` | 200 | 109.0 | 22.8 | 76.6 | 0.0 |
| 376 | `/vrps/333/send_for_approval` | 303 | 103.0 | — | 33.0 | 0.0 |
| 792 | `/modules/access-control/records/178513/edit` | 200 | 100.0 | 45.9 | 49.5 | 0.0 |
| 752 | `/modules/user-hierarchy-mapping` | 200 | 87.0 | 35.0 | 47.2 | 5.8 |
| 819 | `/modules/approval-master` | 200 | 82.0 | 17.8 | 61.7 | 0.0 |
| 945 | `/jj-quizzes` | 200 | 78.0 | 21.6 | 26.6 | 0.7 |
| 672 | `/modules/state-master` | 200 | 72.0 | 16.1 | 46.1 | 0.3 |
| 814 | `/modules/approval-master` | 200 | 66.0 | 18.4 | 45.9 | 0.0 |
| 957 | `/farmer-news` | 200 | 53.0 | 37.4 | 8.4 | 0.0 |
| 961 | `/farmer-videos` | 200 | 52.0 | 19.9 | 10.7 | 0.0 |
| 953 | `/farmer-app-logins` | 200 | 50.0 | 18.9 | 15.5 | 0.0 |
| 742 | `/users` | 200 | 41.0 | 32.0 | 6.7 | 0.7 |
| 836 | `/afls` | 200 | 40.0 | 27.1 | 9.2 | 0.0 |
| 844 | `/target_mappings/vrp_mappings` | 200 | 38.0 | 0.3 | 19.7 | 1.8 |
| 970 | `/farmer-app-logins` | 200 | 38.0 | 18.6 | 8.5 | 0.0 |
| 975 | `/farmer-app-logins` | 200 | 38.0 | 12.5 | 13.2 | 0.0 |
| 712 | `/asa360-mapping` | 200 | 35.0 | 12.4 | 10.2 | 0.2 |
| 923 | `/modules/jeevika-jankar-observation-list` | 200 | 35.0 | 13.8 | 11.7 | 0.2 |
| 771 | `/users` | 200 | 34.0 | 26.0 | 5.2 | 2.4 |
| 965 | `/farmer-app-logins` | 200 | 34.0 | 14.6 | 8.3 | 0.0 |
| 738 | `/modules/vrp-activity-list` | 200 | 31.0 | 21.0 | 4.0 | 0.3 |
| 717 | `/modules/project-master` | 200 | 30.0 | 21.8 | 3.2 | 0.7 |
| 787 | `/modules/access-control-list` | 200 | 29.0 | 20.0 | 5.2 | 2.3 |
| 1012 | `/target_mappings/vrp_mappings` | 200 | 27.0 | 0.2 | 15.9 | 0.0 |
| 579 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 21.0 | — | 3.2 | 0.0 |
| 728 | `/modules/activity-group-list` | 200 | 21.0 | 12.4 | 3.8 | 0.7 |
| 949 | `/farmer360` | 200 | 21.0 | 14.5 | 3.5 | 0.0 |
| 677 | `/modules/stakeholder-master` | 200 | 20.0 | 13.8 | 3.2 | 0.1 |
| 797 | `/modules/add-vrp-type` | 200 | 17.0 | 12.1 | 3.1 | 0.0 |
| 767 | `/modules/jeevika-jankar-transfer-list` | 200 | 16.0 | 10.2 | 3.1 | 0.1 |
| 101 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 13.0 | — | 9.3 | 0.0 |
| 308 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 11.0 | — | 4.4 | 0.0 |
| 317 | `/login` | 302 | 11.0 | — | 6.6 | 2.4 |
| 216 | `/login` | 200 | 10.0 | 5.6 | 3.4 | 0.0 |
| 264 | `/login` | 200 | 10.0 | 6.6 | 1.7 | 1.0 |
| 249 | `/login` | 302 | 9.0 | — | 3.4 | 0.8 |
| 282 | `/login` | 200 | 9.0 | 4.8 | 2.5 | 0.0 |
| 500 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 9.0 | — | 3.9 | 0.0 |
| 522 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 9.0 | — | 2.9 | 0.0 |
| 269 | `/login` | 302 | 8.0 | — | 2.9 | 0.0 |
| 473 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 8.0 | — | 1.9 | 0.0 |
| 983 | `/` | 302 | 7.0 | — | 1.2 | 0.5 |
| 19 | `/` | 302 | 6.0 | — | 1.8 | 0.0 |
| 80 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 6.0 | — | 1.3 | 0.0 |
| 160 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 6.0 | — | 3.1 | 0.0 |
| 278 | `/login` | 302 | 6.0 | — | 0.0 | 0.0 |
| 8 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.2 | 0.0 |
| 115 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.3 | 0.0 |
| 180 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.2 | 0.0 |
| 202 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.5 | 0.0 |
| 226 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.4 | 0.0 |
| 240 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.2 | 0.0 |
| 294 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.3 | 0.0 |
| 392 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.3 | 0.0 |
| 419 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.4 | 0.0 |
| 536 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.2 | 0.0 |
| 564 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.3 | 0.0 |
| 607 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5.0 | — | 1.2 | 0.0 |
| 28 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.1 | 0.0 |
| 336 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.2 | 0.0 |
| 364 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.4 | 0.0 |
| 435 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.2 | 0.0 |
| 505 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.3 | 0.0 |
| 566 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.2 | 0.0 |
| 653 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 4.0 | — | 1.2 | 0.0 |
| 44 | `/rails/active_storage/blobs/redirect/[signed-path]` | 302 | 3.0 | — | 1.0 | 0.0 |
| 258 | `/login` | 302 | 3.0 | — | 0.0 | 0.0 |
| 164 | `/rails/active_storage/disk/[signed-path]` | 200 | 2.0 | — | 0.0 | 0.0 |
| 188 | `/` | 302 | 2.0 | — | 0.0 | 0.0 |
| 212 | `/modules/jeevika-jankar-bill-process` | 302 | 2.0 | — | 0.0 | 0.0 |
| 583 | `/rails/active_storage/disk/[signed-path]` | 200 | 2.0 | — | 0.0 | 0.0 |
| 12 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 32 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 48 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 84 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 105 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 119 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 184 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 206 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 230 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 244 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 298 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 312 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 340 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 368 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 396 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 423 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 439 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 477 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 509 | `/rails/active_storage/disk/[signed-path]` | 304 | 1.0 | — | 0.0 | 0.0 |
| 513 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 517 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 526 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 540 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 559 | `/rails/active_storage/disk/[signed-path]` | 304 | 1.0 | — | 0.0 | 0.0 |
| 573 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 574 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 611 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |
| 657 | `/rails/active_storage/disk/[signed-path]` | 200 | 1.0 | — | 0.0 | 0.0 |

## IDs without a completion in the excerpt

- Line unknown: `start absent` (ID `657b7ddf`).
- Line unknown: `start absent` (ID `0a5c6f2f`).
- Line unknown: `start absent` (ID `90383691`).
- Line 1030: `/admin/config.php` (ID `120707a7`).

## Every slow SQL marker

| Log lines | Logged source | Count | Total ms | Maximum ms |
|---|---|---:|---:|---:|
| 721, 858 | `app/controllers/modules_controller.rb:17011` | 2 | 3773.2 | 2535.7 |
| 495, 620 | `app/controllers/modules_controller.rb:16537` | 2 | 3087.2 | 1676.0 |
| 425 | `app/controllers/modules_controller.rb:16561` | 1 | 1711.5 | 1711.5 |
| 864 | `app/services/module_record_read_query.rb:30` | 1 | 1335.0 | 1335.0 |
