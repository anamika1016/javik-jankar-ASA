# 10 November: request-by-request rescan

Baseline for behavior comparison: `c480b27`. This report rechecks the same supplied attachment, not fresh post-deploy production logs. Duplicate copies of the same request event are counted once. Signed attachment paths, filenames, IPs and query parameters are omitted.

All **94 request IDs** were inspected: **90 Completed events** (82 HTTP 200, eight HTTP 302), plus **four RoutingErrors without a Completed event**. One completed request starts before a pasted tail segment. Thirty completed requests exceed 1,000 ms. The four errors were missed by the earlier completed-only summary.

## Additional fixes and behavior review

- JJ edit GP/village saved-name lookup now fetches each selection in one batch instead of one SELECT per numeric ID. Exact name-key priority, saved order, duplicate removal, leading zeros, missing/overflow IDs, text labels and legacy inactive/deleted selections are retained. Each invocation still reads fresh records; no new stale record cache.
- `/favicon.ico` was referenced by the layout but absent. Added an ICO generated from the existing `public/icon.png` (16/32/48 px). It can be served as a static file instead of reaching Rails routing.
- Previous request-local fuzzy matching keeps the existing algorithm. Exact/fuzzy/role-suffix, true/false result reuse, copied input keys, mutable normalized results, bounded memory and separate controller instances are covered. User save/validation form paths and location escaping/invalidation were rechecked.

## Additional measured result

A rollback-only local benchmark with 100 distinct saved GP/village selections compared original methods against the batched methods. Complete returned name arrays matched. With SQL query caching disabled, SELECTs dropped **200 → 2** and helper time **29.94 → 3.60 ms**. This is synthetic helper timing, not production edit-page latency. All three ICO sizes were decoded and compared to the existing PNG using the encoder resizing settings.

## Remaining work, not claimed solved

- Cold JJ edit DISTINCT location label queries: five slow markers at the same source, including four on one edit, still require PostgreSQL profiling on production-sized data. Saved-ID batching removes separate N+1 reads, not these DISTINCT scans.
- Cold location JSON projections on other-target and JJ forms still have 1.5–1.7 second SQL markers. Existing revision caches help warm reads; these cold timings are not eliminated by CPU optimizations.
- Training list ranking and training-form scalar dropdown reads still have 1.3–1.6 second SQL markers. Local synthetic tests cannot establish the production query plan.
- External JJ catalogue spends ~7.3 seconds wall time versus ~104 ms process CPU. Existing caching is present; no new stale-data TTL or business behavior change was introduced.
- Dashboard source probes/aggregates, completed-payment rendering, bill invoice/download rendering and large browser location payloads remain latency candidates. Logs do not isolate every cost; no fabricated after-deploy speed or universal 5 ms claim.
- `/.env`, POST `/`, and `/sitemap.xml` are unmatched routes in this log. Their logged RoutingErrors do not prove that secrets were served or that a business page failed. No new routes were added for them.

## Every request

Rails durations overlap; SQL and GC must not be added to total time. “—” means the field/event is absent.

| First line | Request ID | Request | Status/event | Total ms | Views ms | SQL ms | GC ms | Slow stages |
|---:|---|---|---|---:|---:|---:|---:|---|
| 12 | 73a6b3a8 | `GET /` | 302 | 212 | — | 21.4 | 60.8 | — |
| 16 | d9c6af4f | `GET /dashboard` | 200 | 3119 | 94.4 | 402.9 | 750.8 | — |
| 18 | 2f8fb496 | `GET /` | 302 | 7 | — | 1.6 | 0.0 | — |
| 22 | 1ca2038f | `GET /dashboard` | 200 | 1427 | 135.3 | 551.1 | 249.1 | — |
| 28 | a1fdfaa4 | `GET /modules/jeevika-jankar-bill-process` | 200 | 414 | 138.5 | 235.3 | 21.2 | — |
| 33 | c48b8561 | `GET /modules/jeevika-jankar-bill-list` | 200 | 7984 | 7205.6 | 581.0 | 1389.3 | module_records.load 384.2 ms; module_records 506.3 ms |
| 40 | 49d6fa03 | `GET /modules/jeevika-jankar-observation-list` | 200 | 19 | 8.1 | 5.3 | 0.0 | — |
| 45 | fb736874 | `GET /modules/jeevika-jankar-payment-list` | 200 | 2616 | 1230.8 | 210.7 | 430.9 | module_records 1233.4 ms |
| 51 | bfa48e20 | `GET /modules/jeevika-jankar-payment-list-detail` | 200 | 1293 | 155.2 | 61.9 | 338.2 | module_records 1124.2 ms |
| 57 | befaf132 | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 82 | 61.1 | 13.7 | 14.0 | — |
| 62 | 3479cbec | `GET /modules/training-form` | 200 | 2302 | 510.0 | 1790.0 | 100.7 | — |
| 68 | be7c4289 | `GET /modules/training-form-list` | 200 | 1686 | 290.5 | 1342.2 | 16.5 | module_records 1388.1 ms |
| 75 | 1d16ad3a | `GET /modules/other-target` | 200 | 8477 | 6698.1 | 1717.3 | 1892.2 | — |
| 81 | e80d9c20 | `GET /modules/other-target-list` | 200 | 569 | 466.1 | 29.1 | 180.9 | — |
| 86 | 452b3bd6 | `GET /modules/other-target-with-farmer` | 200 | 8582 | 6930.8 | 1608.2 | 2034.7 | — |
| 92 | d6281062 | `GET /modules/other-target-with-farmer-list` | 200 | 368 | 260.7 | 20.3 | 177.0 | — |
| 97 | 6ac8a522 | `GET /afls` | 200 | 120 | 74.3 | 40.6 | 4.3 | — |
| 101 | f6fc792b | `GET /` | 200 | 13 | 10.7 | 0.0 | 1.4 | — |
| 105 | f939190f | `GET /target_mappings` | 200 | 5759 | 1852.0 | 102.7 | 156.3 | — |
| 109 | 0a167ed4 | `GET /target_mappings/vrp_mappings` | 200 | 115 | 0.6 | 48.4 | 11.8 | — |
| 113 | 5271c03d | `GET /target_mappings/list` | 200 | 1378 | 781.4 | 15.8 | 297.4 | — |
| 118 | ed0ac9e1 | `GET /jj-mapped-farmers` | 200 | 7392 | 24.5 | 54.6 | 19.1 | external.jj_catalogue 7344.3 ms |
| 123 | 51f4f424 | `GET /modules/add-vrp-type` | 200 | 12 | 10.4 | 0.0 | 0.2 | — |
| 128 | c5114b8f | `GET /modules/add-vrp-type` | 200 | 15 | 12.3 | 0.0 | 2.2 | — |
| 133 | fb4fc6dc | `GET /vrps/new` | 200 | 9167 | 6133.6 | 2619.6 | 2063.2 | vrp.location_attribute 7374.3 ms |
| 139 | 2a1c766b | `GET /vrps/new` | 200 | 9106 | 6221.1 | 2574.8 | 2007.6 | vrp.location_attribute 7682.0 ms |
| 146 | 6a3b5419 | `GET /vrps` | 200 | 316 | 27.5 | 68.3 | 14.1 | — |
| 150 | 59d33d6e | `GET /login` | 200 | 99 | — | 113.1 | 0.4 | — |
| 154 | 52f88f83 | `POST /login` | 302 | 109 | — | 118.2 | 12.3 | — |
| 159 | 1a9e0d8e | `GET /dashboard` | 200 | 770 | 24.4 | 631.1 | 4.1 | — |
| 163 | 5026d6b6 | `GET /modules/jeevika-jankar-bill-list` | 200 | 1468 | 353.4 | 684.3 | 249.1 | module_records.load 593.3 ms; module_records 882.6 ms |
| 170 | c0597ca8 | `GET /` | 200 | 6 | 4.8 | 0.0 | 0.0 | — |
| 174 | ee16df21 | `POST /login` | 302 | 8 | — | 2.6 | 0.0 | — |
| 179 | 867bea03 | `GET /dashboard` | 200 | 1155 | 80.1 | 593.0 | 123.9 | — |
| 183 | f4fa1b33 | `GET /modules/jeevika-jankar-bill-list` | 200 | 5522 | 623.4 | 243.7 | 1141.4 | module_records 4691.6 ms |
| 189 | 644afe0f | `GET /modules/jeevika-jankar-bill-list` | 200 | 6025 | 649.7 | 240.0 | 1393.2 | module_records 5199.2 ms |
| 192 | dd233f27 | `GET /modules/jeevika-jankar-bill-list` | 200 | 916 | 656.3 | 162.1 | 89.0 | — |
| 200 | ca8cec66 | `GET /modules/jeevika-jankar-bill-list` | 200 | 1207 | 995.7 | 153.8 | 309.5 | — |
| 205 | f425d610 | `GET /logout` | 302 | 2 | — | 0.0 | 0.0 | — |
| 209 | 2ce3b851 | `GET /login` | 200 | 7 | 4.5 | 0.0 | 0.0 | — |
| 213 | 5c271ff8 | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 2659 | 2592.3 | 58.2 | 983.6 | — |
| 218 | ee302a49 | `GET /modules/jeevika-jankar-completed-payment-list` | 200 | 2194 | 2133.4 | 50.5 | 658.2 | — |
| 223 | 916b3938 | `GET /modules/jeevika-jankar-payment-list` | 200 | 2976 | 1279.7 | 305.2 | 682.8 | module_records 1469.8 ms |
| 229 | 5b7573e6 | `GET /rails/active_storage/blobs/redirect/[signed-path]` | 302 | 8 | — | 1.6 | 0.0 | — |
| 234 | 4cca1178 | `GET /rails/active_storage/disk/[signed-path]` | 200 | 2 | — | 0.0 | 0.0 | — |
| 238 | 6a8faede | `GET /modules/jeevika-jankar-bill-list/records/182898/download_bill` | 200 | 1944 | 1772.3 | 143.3 | 585.0 | — |
| 243 | 0f37c88c | `GET /rails/active_storage/blobs/redirect/[signed-path]` | 302 | 7 | — | 1.3 | 0.0 | — |
| 248 | 46e9919e | `GET /rails/active_storage/disk/[signed-path]` | 200 | 1 | — | 0.0 | 0.0 | — |
| 252 | b52b0e8d | `GET /favicon.ico` | RoutingError; no Completed event | — | — | — | — | — |
| 256 | d117cde1 | `GET /.env` | RoutingError; no Completed event | — | — | — | — | — |
| 260 | 3bae3f1a | `POST /` | RoutingError; no Completed event | — | — | — | — | — |
| 264 | 9a47309c | `GET /modules/jeevika-jankar-bill-list/records/182466/download_bill` | 200 | 1300 | 1046.3 | 218.9 | 173.3 | — |
| 269 | 5a1d2b8a | `GET /rails/active_storage/blobs/redirect/[signed-path]` | 302 | 5 | — | 1.6 | 0.0 | — |
| 274 | 38de9fc8 | `GET /rails/active_storage/disk/[signed-path]` | 200 | 1 | — | 0.0 | 0.0 | — |
| 278 | c5bac97e | `GET /sitemap.xml` | RoutingError; no Completed event | — | — | — | — | — |
| 286 | b86dbec9 | `GET /users/new` | 200 | 9398 | 774.3 | 280.5 | 2368.1 | user.form_options 8540.9 ms |
| 287 | 5d54821a | `GET /users` | 200 | 42 | 34.0 | 4.1 | 5.2 | — |
| 291 | bf6a6050 | `GET /users/112/edit` | 200 | 497 | 376.9 | 46.6 | 91.7 | — |
| 296 | e6e52ea5 | `GET /dashboard` | 200 | 563 | 24.6 | 421.6 | 13.9 | — |
| 300 | 7e640117 | `GET /users/new` | 200 | 9989 | 864.8 | 288.8 | 2753.6 | user.form_options 9062.0 ms |
| 311 | 890eee7b | `partial request (start absent)` | 200 | 166 | 14.2 | 46.5 | 27.0 | — |
| 314 | b07388c7 | `GET /modules/jeevika-jankar-bill-process/jeevika_jankar_bill_target_rows` | 200 | 643 | 0.4 | 274.1 | 44.1 | — |
| 318 | 6bbcdcfe | `GET /vrps/7/edit` | 200 | 5467 | 618.4 | 4368.8 | 206.1 | — |
| 327 | f1ee94b6 | `GET /modules/jeevika-jankar-bill-list` | 200 | 315 | 10.8 | 50.9 | 73.4 | module_records 299.2 ms |
| 333 | aacec409 | `GET /modules/jeevika-jankar-bill-list` | 200 | 243 | 10.3 | 56.0 | 0.0 | — |
| 338 | 70e7a79c | `GET /vrps` | 200 | 328 | 38.5 | 77.5 | 44.5 | — |
| 342 | 563e740a | `GET /vrps/approvals` | 200 | 3767 | 32.8 | 37.8 | 1045.7 | — |
| 346 | c3c411e2 | `GET /modules/jeevika-jankar-bill-process` | 200 | 118 | 11.3 | 27.5 | 15.0 | — |
| 351 | a64a8fa6 | `GET /modules/jeevika-jankar-bill-list` | 200 | 218 | 9.8 | 43.1 | 24.0 | — |
| 356 | ec8b7bf7 | `GET /modules/jeevika-jankar-bill-list` | 200 | 265 | 11.0 | 37.0 | 56.6 | — |
| 361 | 871db46d | `GET /modules/jeevika-jankar-bill-process` | 200 | 99 | 10.0 | 22.8 | 18.6 | — |
| 366 | 9de40750 | `GET /modules/jeevika-jankar-bill-process/jeevika_jankar_bill_target_rows` | 200 | 8 | 0.2 | 3.1 | 0.0 | — |
| 370 | 91e02886 | `GET /modules/other-target-list` | 200 | 525 | 16.2 | 67.1 | 78.3 | module_records.visibility 451.7 ms; module_records 464.1 ms |
| 377 | 9268c2b2 | `GET /modules/training-form-list` | 200 | 1507 | 47.2 | 183.0 | 328.4 | module_records.visibility 1274.6 ms; module_records 1419.9 ms |
| 380 | 24f47c4e | `GET /modules/training-form-list` | 200 | 1380 | 62.8 | 173.6 | 295.1 | module_records.visibility 1138.3 ms; module_records 1294.4 ms |
| 391 | 49d44b7b | `GET /modules/jeevika-jankar-bill-process` | 200 | 121 | 15.9 | 20.0 | 22.7 | — |
| 396 | 162cc1ae | `GET /modules/jeevika-jankar-bill-process` | 200 | 100 | 10.4 | 22.7 | 9.0 | — |
| 401 | d488d1bb | `GET /modules/jeevika-jankar-bill-process` | 200 | 85 | 8.9 | 28.3 | 0.0 | — |
| 406 | ca3e9d15 | `GET /modules/jeevika-jankar-bill-list` | 200 | 276 | 9.5 | 43.9 | 44.2 | module_records 261.5 ms |
| 412 | 1bc2ad87 | `GET /modules/approval-master` | 200 | 161 | 28.5 | 130.8 | 0.9 | — |
| 417 | 6444509a | `GET /modules/approval-list` | 200 | 104 | 78.2 | 10.4 | 19.2 | — |
| 422 | ed3d5939 | `GET /modules/jeevika-jankar-bill-list` | 200 | 264 | 16.0 | 51.6 | 38.5 | — |
| 425 | ef06798b | `GET /vrp-agreements` | 200 | 601 | 83.2 | 438.6 | 18.9 | — |
| 431 | 5496c48e | `GET /users` | 200 | 37 | 28.9 | 4.4 | 1.8 | — |
| 437 | aafb9d07 | `GET /modules/jeevika-jankar-bill-list` | 200 | 309 | 12.9 | 78.5 | 45.9 | module_records 291.1 ms |
| 443 | c55c4e23 | `GET /modules/jeevika-jankar-bill-list` | 200 | 276 | 11.0 | 54.1 | 37.5 | module_records 256.3 ms |
| 449 | b3071e24 | `GET /modules/jeevika-jankar-bill-list` | 200 | 262 | 18.2 | 44.0 | 44.5 | — |
| 452 | e138039d | `GET /modules/jeevika-jankar-bill-list` | 200 | 310 | 14.5 | 52.8 | 54.0 | module_records 289.3 ms |
| 481 | 590d9ae2 | `GET /modules/jeevika-jankar-bill-process` | 200 | 115 | 10.8 | 37.6 | 13.2 | — |
| 486 | da39c7a2 | `GET /modules/jeevika-jankar-bill-process` | 200 | 155 | 19.8 | 68.0 | 6.6 | — |
| 491 | 5c413f74 | `GET /modules/jeevika-jankar-bill-process` | 200 | 91 | 10.2 | 18.9 | 5.0 | — |
| 496 | 0bfe829f | `GET /modules/jeevika-jankar-bill-process` | 200 | 141 | 20.9 | 44.0 | 11.4 | — |
| 501 | 8b094086 | `GET /modules/jeevika-jankar-bill-process` | 200 | 82 | 10.7 | 17.3 | 3.9 | — |
| 506 | 384912fd | `GET /modules/jeevika-jankar-bill-process` | 200 | 94 | 11.3 | 21.5 | 5.1 | — |

## Every slow SQL marker

Sources use line numbers from the deployed code in the log; local edits shift those lines.

| Log line | Request ID | SQL ms | Logged source |
|---:|---|---:|---|
| 65 | 3479cbec | 1610.7 | `app/controllers/modules_controller.rb:16989` |
| 71 | be7c4289 | 1316.8 | `app/services/module_record_read_query.rb:30` |
| 78 | 1d16ad3a | 1608.9 | `app/controllers/modules_controller.rb:16517` |
| 89 | 452b3bd6 | 1485.2 | `app/controllers/modules_controller.rb:16517` |
| 135 | fb4fc6dc | 1665.5 | `app/controllers/vrps_controller.rb:2105` |
| 141 | 2a1c766b | 775.0 | `app/controllers/vrps_controller.rb:2244` |
| 142 | 2a1c766b | 1545.4 | `app/controllers/vrps_controller.rb:2105` |
| 321 | 6bbcdcfe | 827.5 | `app/controllers/vrps_controller.rb:2244` |
| 322 | 6bbcdcfe | 841.4 | `app/controllers/vrps_controller.rb:2244` |
| 323 | 6bbcdcfe | 978.7 | `app/controllers/vrps_controller.rb:2244` |
| 324 | 6bbcdcfe | 1247.8 | `app/controllers/vrps_controller.rb:2244` |

## Verification after rescan

- Focused combined suite: **65 tests / 1,215 assertions, zero failures/errors**. Includes all previous CPU changes and the new saved-location batching, successful saves, four validation/error render paths, cache invalidation/escaping and staff/cluster bill visibility.
- Broader controller/service run: **710 tests / 6,865 assertions, 26 failures and eight errors**; 676 tests passed. The entire suite is not clean.
- To check regression status, every changed method in UsersController, ModulesController and VrpsController, plus the user-form callback, was restored from `c480b27` **in memory** in a separate test process. The three new test files were excluded there because they assert new optimization properties. Baseline: **702 tests / 5,987 assertions, 26 failures and eight errors**. All **34 failing/error test names match exactly**, with no new failing test in the changed implementation.
- Existing problems span training attendance/visibility/photo expectations, dashboard/bill totals and access/menu expectations, OTP mock/API checks, plus incomplete nil/mock request fixtures. They were not changed to force a green run; these may include existing product issues as well as outdated test expectations and need separate review.
- Syntax/diff checks pass. Static favicon decoded correctly. No production deployment or post-patch production timings were obtained.

### Matching baseline failure/error names

- `Api::V1::FarmerTargetApisControllerTest#test_training_list_corrects_stale_total_without_confusing_registered_farmers_and_attendance`
- `Api::V1::FarmerTargetUpdateApiTest#test_a_farmer_training_edit_saves_and_recomputes_the_totals`
- `Api::V1::SidebarMenusControllerTest#test_blank_can_view_does_not_grant_menu_access`
- `Api::V1::SidebarMenusControllerTest#test_farmer_target_access_does_not_expose_sibling_menus_without_separate_access`
- `ApiVrpReadScalingTest#test_approval-related_JJ_visibility_batches_history_reads_without_changing_matching_rows`
- `ApiVrpReadScalingTest#test_other_target_compact_browser_payload_expands_to_the_original_mappings`
- `JeevikaBillWorksheetAndCcTest#test_a_cluster_incharge_sees_the_bills_of_the_Jeevika_Jankars_under_them`
- `LocationCatalogueCacheTest#test_location_master_saved_records_reuse_payloads_and_invalidate_after_a_direct_edit`
- `ModuleLookupPerformanceTest#test_bill_totals_omit_unused_farmer_display_data_and_preserve_target_summary`
- `ModuleLookupPerformanceTest#test_dashboard_office_visibility_preserves_normalized_FCO_and_TO_matches`
- `ModuleReadPerformanceTest#test_API_dashboard_batches_fallback_VRP_mappings_while_preserving_mapped_farmer_ids`
- `ModuleReadPerformanceTest#test_dashboard_batches_FCO_counts_while_preserving_aliases,_distinct_JJ_and_month_matching`
- `ModuleReadPerformanceTest#test_other_target_contact_numbers_are_batch_loaded_with_mapping_precedence_and_legacy_fallbacks`
- `SessionsControllerTest#test_forgot_password_otp_api_returns_json_failure_when_sms_gateway_fails`
- `SessionsControllerTest#test_forgot_password_otp_api_returns_json_success`
- `TrainingFormListScopeTest#test_grouped_training_attendance_uses_one_coherent_session_count_and_retains_selected_farmer_count`
- `TrainingFormVisibilityTest#test_FCOC_sees_their_office_JJ_but_not_another_office`
- `TrainingFormVisibilityTest#test_assigned_approver_sees_training_outside_their_CC_mapping`
- `TrainingFormVisibilityTest#test_training_visibility_follows_the_registered_CC,_not_a_similar_name`
- `TrainingPhotoViewsTest#test_named_views_replace_old_input_and_keep_report_photo_compatibility`
- `TrainingPhotoViewsTest#test_oversized_and_non-image_named_uploads_fail_before_any_file_is_stored`
- `VrpDashboardTest#test_admin_sees_vrp_menu_and_can_select_it_in_access_control`
- `VrpDashboardTest#test_dashboard_and_bill_summary_count_distinct_training_participants_across_sessions_beyond_mapped_target_size`
- `VrpDashboardTest#test_dashboard_counts_the_same_farmer_once_for_each_completed_training_activity`
- `VrpDashboardTest#test_jeevika_bill_appears_in_approver_login_after_send_for_approval`
- `VrpDashboardTest#test_jeevika_bill_creator_sees_submitted_bill_in_default_pending_list`
- `VrpDashboardTest#test_jeevika_jankar_approval_starts_with_first_approver_from_creator_channel`
- `VrpDashboardTest#test_mapped_village_dashboard_count_uses_mapping_rows_and_allows_delete`
- `VrpDashboardTest#test_other_target_forms_accept_completion_date_without_legacy_date_key`
- `VrpDashboardTest#test_partial_target_requires_selected_farmers_and_blocks_same_month_reassignment`
- `VrpDashboardTest#test_target_mapping_keeps_training_targets_for_mixed_training_and_other_activity_selection`
- `VrpDashboardTest#test_target_mapping_location_dropdowns_fall_back_to_saved_target_rows`
- `VrpDashboardTest#test_vrp_sees_own_dashboard_data_and_read_only_targets`
- `VrpDashboardTest#test_vrp_training_form_shows_only_target_assigned_farmers`
