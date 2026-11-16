# File-by-file behavior review — 16 November 2026

Reviewed the complete pending diff and newly added source, views, scripts and tests, and checked their callers and view branches. This pass found no additional regression requiring an application-code change. Earlier intentional delivery changes remain: Office List and blank admin JJ picker load remote content in separate authorized frames. This is not a claim that loading behavior is literally identical or that every production case is proven.

## Independent baseline comparison

Exported original commit `f0f51c0` into `/tmp/jj-file-review-baseline-20261116` and ran its tests with the same Ruby, isolated PostgreSQL database, disabled external HTTP and seed `25576`. This covers unchanged model and helper files as well as controller, integration and service tests.

| Check | Original commit | Current pending code |
|---|---|---|
| All Ruby tests | 922 tests, 8,058 assertions | 949 tests, 8,247 assertions |
| Ruby failures/errors | 23 failures, 9 errors | Same 23 failures, 9 errors |
| Failing/error test names | 32 | Exactly the same 32; no new names |
| Error exception summaries | 9 | Same exception classes/messages |
| All JavaScript (same Node/runtime permissions) | 42/43 cases pass | 44/45 cases pass |
| JavaScript failure | English translate-cookie expiry assertion | Same assertion and message |

Assertions containing database-generated IDs or complete HTML naturally differ between runs; failure summaries were reviewed for that distinction. Existing failures were not suppressed or changed to green. Broader model/helper coverage adds one existing model error relative to the earlier 31-failure/error controller/service/integration inventory. The complete 32-name list is in `tmp/file_review_baseline_comparison.json`.

## Successful repeated checks

- Focused behavior regressions, reported seed `19875`: **224 tests, 1,506 assertions, zero failures/errors**.
- Fresh synthetic cold/warm page renders: **46/46 return 200**, no exceptions.
- Fresh role requests: **329**, comprising 308×200, 9×401, 9×403, 2×302 and 1×422; no 5xx or exceptions. This rerun includes the final selected-bill-history changes.
- Python interleaved-log regression: **1 test passes**.
- Syntax checks: 28 changed/new Ruby, Python and CJS files pass; `layout.js` also parses as a JavaScript module.
- `git diff --check` passes.

The focused tests cover selected form action/data, source/slug boundaries, permissions and denied requests, bill/detail/history scoping, master pagination/search, label ordering/duplicates/fallbacks, JSON types/nulls/escaping, active/deleted filters, cache source/code invalidation, actual cross-process cold-fill locking, unavailable cache fallback, lazy block/FCO options and deferred office/JJ content. The earlier synthetic before/after audit separately checks identical entry/edit HTML and returned label/dropdown/GP results.

## Reviewed files

The inventory below covers all 37 files pending at the start of this review. Reports are historical snapshots; their test counts apply to the runs they describe. The added review report itself is not included in that initial count.

| File | Review / check |
|---|---|
| `app/controllers/application_controller.rb` | Diff and caller/view review; syntax; focused and full Ruby regressions; page/role renders |
| `app/controllers/modules_controller.rb` | Diff and caller/view review; syntax; focused and full Ruby regressions; page/role renders |
| `app/controllers/target_mappings_controller.rb` | Diff and caller/view review; syntax; focused and full Ruby regressions; page/role renders |
| `app/controllers/users_controller.rb` | Diff and caller/view review; syntax; focused and full Ruby regressions; page/role renders |
| `app/controllers/vrps_controller.rb` | Diff and caller/view review; syntax; focused and full Ruby regressions; page/role renders |
| `app/javascript/layout.js` | Table initialization/frame handler diff; module syntax; complete JS baseline comparison |
| `app/services/catalogue_read_cache.rb` | Read/cache semantics review; syntax; source invalidation, parity and full regressions |
| `app/services/module_field_options_cache.rb` | Read/cache semantics review; syntax; source invalidation, parity and full regressions |
| `app/services/module_record_read_query.rb` | Read/cache semantics review; syntax; source invalidation, parity and full regressions |
| `app/services/shared_catalogue_cache.rb` | Read/cache semantics review; syntax; source invalidation, parity and full regressions |
| `app/views/modules/_office_list.html.erb` | Rendered form/frame/table data, escaping, fallback and export target review; controller/render regressions |
| `app/views/modules/_office_list_frame.html.erb` | Rendered form/frame/table data, escaping, fallback and export target review; controller/render regressions |
| `app/views/modules/show.html.erb` | Rendered form/frame/table data, escaping, fallback and export target review; controller/render regressions |
| `app/views/target_mappings/_jj_api_user_select.html.erb` | Rendered form/frame/table data, escaping, fallback and export target review; controller/render regressions |
| `app/views/target_mappings/jj_mapped_farmers.html.erb` | Rendered form/frame/table data, escaping, fallback and export target review; controller/render regressions |
| `app/views/target_mappings/jj_user_options.html.erb` | Rendered form/frame/table data, escaping, fallback and export target review; controller/render regressions |
| `config/routes.rb` | Route-only addition reviewed; syntax; authorized/denied frame endpoint tests |
| `docs/module-record-detail-performance-2026-11-16.md` | Claims, local-vs-production limitations and validation results reviewed |
| `docs/new-log-performance-2026-11-16.md` | Claims, local-vs-production limitations and validation results reviewed |
| `script/analyze_request_performance.py` | Read-only/rollback scope, baseline comparison and external-call handling reviewed; syntax; existing audit executions |
| `script/external_catalogue_navigation_audit.rb` | Read-only/rollback scope, baseline comparison and external-call handling reviewed; syntax; existing audit executions |
| `script/module_record_detail_read_audit.rb` | Read-only/rollback scope, baseline comparison and external-call handling reviewed; syntax; existing audit executions |
| `script/new_log_hotspot_audit.rb` | Read-only/rollback scope, baseline comparison and external-call handling reviewed; syntax; existing audit executions |
| `script/warm_form_catalogues.rb` | Read-only/rollback scope, baseline comparison and external-call handling reviewed; syntax; existing audit executions |
| `test/controllers/bill_detail_history_read_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/jj_mapped_farmers_deferred_catalogue_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/module_read_performance_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/module_record_entry_read_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/office_list_deferred_loading_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/selected_module_record_labels_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/shared_form_catalogue_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/controllers/target_entry_catalogue_loading_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/javascript/office_frame_table_test.cjs` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/javascript/target_mapping_block_farmer_loading_test.cjs` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/scripts/test_analyze_request_performance.py` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/services/module_field_options_cache_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |
| `test/services/shared_catalogue_cache_test.rb` | Assertions/fixtures/cleanup reviewed; included in matching Ruby/JS/Python test run |

## Limits and artifacts

No production deployment, business-data write or change to existing authorization/billing formulas was made during this review. Production-only caching is exercised by injected shared-store tests, including separate processes; a real production rollout/concurrency test remains outstanding. External APIs were disabled or mocked. No whole-application “zero issues” or universal 15 ms guarantee follows from these local checks.

Current artifacts: `tmp/file_review_focused_tests.log`, `tmp/file_review_all_tests.log`, `tmp/file_review_all_js.log`, `tmp/file_review_python.log`, `tmp/file_review_render_audit.json`, `tmp/file_review_role_audit.json`, `tmp/file_review_inventory.json`, `tmp/file_review_baseline_comparison.json`. Original-commit logs: `/tmp/jj-file-review-baseline-ruby.log`, `/tmp/jj-file-review-baseline-js.log`.

## Additional edge-case rescan

A later repeat reviewed the cache and authorization boundaries and added three regression cases: URL parameters claiming `admin` cannot grant catalogue access; a signed-out catalogue frame redirects to login without a remote fetch; and direct imports that move records between source modules (without changing `updated_at`), delete them or repopulate an empty catalogue invalidate the correct cache results.

The focused rerun reports seed `25944`: **227 tests, 1,524 assertions, zero failures/errors** (`tmp/edge_rescan_focused_tests.log`). `git diff --check` also passes. No further application-code change was needed in this pass. The preceding full-suite baseline failures and production-verification limitations remain.
