# Final performance and behavior rescan — 13 November 2026

Latest follow-up: [candidate reuse optimization and fresh regression checks](performance-followup-2026-11-13.md).

## Findings and corrections

A genuine fast-path mismatch was found during the broader review. For Other Activity bills, the fast total used a raw achievement-index value, or zero when absent, while the full bill calculation used grouped progress including fallback values and the existing target cap. The fast path now uses that same grouped-progress result. For example, an achievement of 25 against a target of 10 previously produced 25 in fast totals but 10 in the full calculation; both now return the existing full-calculation result, 10. The fallback regression also verifies that an existing completed quantity of 4 is retained rather than replaced with zero.

This is a correction to fast/full calculation parity, not a claim that every historical Bill List value was already identical. Approval rules, permission scope, saved data, and the full calculation were not changed.

Additional optimization: live training fallback uses the existing owner-candidate index to avoid matching unrelated JJs' submissions. It retains the complete matcher, blank-owner fallback, ID/name/username/mobile aliases, original source order and duplicate-ID handling. Empty Other Target monthly datasets now return immediately; direct-ID-only datasets skip unused owner lookup work.

Two earlier test issues were repaired without changing production permissions: the location cache test now has a real Rails test request; the office-visibility performance test checks the helper's existing case/whitespace normalization and explicitly verifies that FCO-prefixed labels are not silently granted extra access.

## Performance and output validation

The training fallback CPU benchmark used 100 synthetic owners and 3,000 monthly records:

| Metric | Before | After |
|---|---:|---:|
| Time | 4,096.52 ms | 245.15 ms |
| Allocations | 16,202,896 | 491,850 |

All 100 achievement results match. This is a fallback-calculation benchmark, not full-page or production latency. Reproduce with `RAILS_ENV=test bundle exec rails runner script/bill_training_fallback_scaling_audit.rb` using an isolated test database.

The final Bill List was also rendered against the authoritative full-calculation reference, including over-target Other Activity submissions (20 bills, 600 monthly Other Target submissions):

| HTTP render | Full-calculation reference | Final fast path |
|---|---:|---:|
| Cold | 192.35 ms | 134.50 ms |
| Warm | 133.32 ms | 75.63 ms |

Visible text, controls, browser data hashes, and HTTP status match on both passes. The earlier 100-bill performance report remains useful as historical evidence of the repeated-scan reduction, but its pre-correction output must not be treated as authoritative for the over-target edge case described above.

## Final checks

- Final combined focused regression suite: **179 tests, 1,035 assertions, zero failures/errors** across performance, billing, approval, permissions, training routing, farmer rendering and dashboard drilldowns.
- 46 cold/warm synthetic page renders: all HTTP 200, no exceptions.
- 329 admin/staff/JJ web/API requests: no server errors or exceptions; response statuses match the original-method role run after generated fixture IDs are normalized. Authorization/validation responses are retained, not counted as successful business operations.
- Complete controller/service/integration suite: **858 tests, 7,670 assertions, 23 failures and 8 errors**. Every remaining failure/error also reproduces with original HEAD production methods. **No final-only failing test was found.** The original-method run had 857 tests, 26 failures and 11 errors; an additional regression case was added between the two runs, and new tests intentionally detect the original slower/mismatching paths. The whole repository is therefore not declared test-clean.
- All JavaScript test files were checked: 15 of 16 file checks pass. The unchanged language-switch test fails because its document stub lacks `getElementById` (four underlying cases); production JavaScript was not changed by this work.
- Ruby syntax and whitespace checks pass.

## Remaining broader-suite issues

These are reproduced baseline issues, not newly introduced failures. Some are incomplete mocks, while others are unresolved test/business-behavior disagreements. They are recorded rather than changing training counts, menu permissions, photo behavior, or approval rules under the performance task.

| Kind | Test | First diagnostic |
|---|---|---|
| Failure | `VrpDashboardTest#test_partial_target_requires_selected_farmers_and_blocks_same_month_reassignment` | `TargetMapping.count` didn't change by 1, but by 0. |
| Failure | `VrpDashboardTest#test_mapped_village_dashboard_count_uses_mapping_rows_and_allows_delete` | Expected: 3 |
| Failure | `VrpDashboardTest#test_admin_sees_vrp_menu_and_can_select_it_in_access_control` | Rendered output differs from the test expectation. |
| Failure | `VrpDashboardTest#test_jeevika_jankar_approval_starts_with_first_approver_from_creator_channel` | --- expected |
| Failure | `VrpDashboardTest#test_other_target_forms_accept_completion_date_without_legacy_date_key` | `ModuleRecord.where(module_slug: 'papl360-target').count` didn't change by 1, but by 0. |
| Failure | `VrpDashboardTest#test_dashboard_counts_the_same_farmer_once_for_each_completed_training_activity` | Expected: "2" |
| Failure | `VrpDashboardTest#test_vrp_training_form_shows_only_target_assigned_farmers` | Expected response to be a <2XX: success>, but was a <302: Found> redirect to <http://www.example.com/login> |
| Failure | `VrpDashboardTest#test_target_mapping_keeps_training_targets_for_mixed_training_and_other_activity_selection` | `TargetMapping.count` didn't change by 2, but by 0. |
| Failure | `VrpDashboardTest#test_jeevika_bill_appears_in_approver_login_after_send_for_approval` | --- expected |
| Failure | `VrpDashboardTest#test_dashboard_and_bill_summary_count_distinct_training_participants_across_sessions_beyond_mapped_target_size` | Expected: "8" |
| Failure | `VrpDashboardTest#test_target_mapping_location_dropdowns_fall_back_to_saved_target_rows` | Expected [] to include "ICS-TM /  / Target ICS". |
| Failure | `VrpDashboardTest#test_jeevika_bill_creator_sees_submitted_bill_in_default_pending_list` | --- expected |
| Failure | `VrpDashboardTest#test_vrp_sees_own_dashboard_data_and_read_only_targets` | Rendered output differs from the test expectation. |
| Failure | `Api::V1::FarmerTargetApisControllerTest#test_training_list_corrects_stale_total_without_confusing_registered_farmers_and_attendance` | Expected: "10" |
| Failure | `TrainingPhotoViewsTest#test_named_views_replace_old_input_and_keep_report_photo_compatibility` | Expected: "photo_close_up_view" |
| Failure | `TrainingPhotoViewsTest#test_oversized_and_non-image_named_uploads_fail_before_any_file_is_stored` | Expected false to be truthy. |
| Failure | `Api::V1::FarmerTargetUpdateApiTest#test_a_farmer_training_edit_saves_and_recomputes_the_totals` | total follows the edited male and female counts. |
| Failure | `TrainingFormListScopeTest#test_grouped_training_attendance_uses_one_coherent_session_count_and_retains_selected_farmer_count` | Expected: "10" |
| Error | `SessionsControllerTest#test_forgot_password_otp_api_returns_json_failure_when_sms_gateway_fails` | NameError: uninitialized constant Minitest::Mock |
| Error | `SessionsControllerTest#test_forgot_password_otp_api_returns_json_success` | NameError: uninitialized constant Minitest::Mock |
| Error | `ApiVrpReadScalingTest#test_approval-related_JJ_visibility_batches_history_reads_without_changing_matching_rows` | NoMethodError: undefined method 'value_for_database' for an instance of String |
| Error | `ApiVrpReadScalingTest#test_other_target_compact_browser_payload_expands_to_the_original_mappings` | NoMethodError: undefined method 'filtered_parameters' for nil |
| Failure | `Api::V1::SidebarMenusControllerTest#test_blank_can_view_does_not_grant_menu_access` | Expected ["Payment List"] to not include "Payment List". |
| Failure | `Api::V1::SidebarMenusControllerTest#test_farmer_target_access_does_not_expose_sibling_menus_without_separate_access` | Expected ["Training Form"] to include "Farmer Training Form". |
| Error | `TrainingFormVisibilityTest#test_assigned_approver_sees_training_outside_their_CC_mapping` | NoMethodError: undefined method 'filtered_parameters' for nil |
| Failure | `TrainingFormVisibilityTest#test_training_visibility_follows_the_registered_CC,_not_a_similar_name` | Expected true to be nil or false |
| Error | `TrainingFormVisibilityTest#test_FCOC_sees_their_office_JJ_but_not_another_office` | NoMethodError: undefined method 'filtered_parameters' for nil |
| Failure | `JeevikaBillWorksheetAndCcTest#test_a_cluster_incharge_sees_the_bills_of_the_Jeevika_Jankars_under_them` | the mapped Jeevika Jankar's bill should be listed. |
| Error | `ModuleReadPerformanceTest#test_API_dashboard_batches_fallback_VRP_mappings_while_preserving_mapped_farmer_ids` | ActiveRecord::NotNullViolation: PG::NotNullViolation: ERROR:  null value in column "aadhar_no" of relation "vrps" violates not-null constraint |
| Failure | `ModuleReadPerformanceTest#test_dashboard_batches_FCO_counts_while_preserving_aliases,_distinct_JJ_and_month_matching` | Expected: 1 |
| Error | `ModuleReadPerformanceTest#test_other_target_contact_numbers_are_batch_loaded_with_mapping_precedence_and_legacy_fallbacks` | NameError: undefined local variable or method 'session' for nil |

## Limits

No production deployment or authenticated live-server measurement was performed. The supplied 84 historical production requests and local rollback-only synthetic audits do not prove a universal 5 ms browser load or absence of every possible issue. Production load, external services, data size, and deployed revision still need real request measurements. All prior worktree edits were retained; the unrelated existing schema diff is outside this performance change.
