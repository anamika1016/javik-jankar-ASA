Modules performance and farm-feature removal (26 October 2026)

Final scope

- Removed all 15 Farmer Farm Information sidebar entries, their routes, controllers, models, views, helper methods, exclusive CSS/JavaScript and import/link concerns.
- Removed unused legacy farm/exit helpers from TargetMappingsController. Dashboard farmer profiles now use AFL; the removed feature no longer supplies fallback names/contact/status for blank AFL fields.
- Added RemoveFarmerFarmInformationFeature migration for the 13 feature tables, with child tables removed before the parent. Historical creation migrations remain intact. Rollback recreates table definitions and foreign keys, but cannot recover deleted rows. Migration has not been applied to development or production.
- Previously requested three dashboard reports remain removed.

Performance and preserved behavior

- LG directory selections use one SELECT, preserving token order, duplicate handling, allowed slugs and slug ownership.
- Training list candidate SQL omits photo/participant payloads. Visibility still runs before the 100-row cap, including older owned records. Full records are hydrated only for final visible rows.
- Select the first 100 with min_by(100), preserving pending-first / created_at / ID ordering without sorting the entire candidate population. All/export requests retain the full result set and payloads.
- Latest revision summaries are selected in SQL using DISTINCT ON and the existing (record_id, id DESC) index. Highest revision ID wins regardless of created_at; older payloads do not instantiate Ruby records.
- Read projections and hydration live in ModuleRecordReadQuery. Revision auto-assignment is attempted once per revision per request.

Validation

- Isolated database: jj_feature_removal_test_20261026. Development and production data were not changed.
- Focused scaling, sidebar, dashboard and training approval regression suite: Final focused suite: 50 tests, 392 assertions passed, including direct comparison of limited-list payload/order with the full-list prefix. The removed-feature API test also passed (1 test, 11 assertions).
- Migration up/down round trip and Rails eager loading (zeitwerk:check) passed in the isolated database.
- JavaScript suite: 10 files passed, 1 language-switch test file failed because its document mock lacks getElementById. The same error reproduces with HEAD layout.js.
- Earlier baseline audit: read/lookup suite has 3 failures and 1 error reproduced with the original HEAD controller (FCO query count, legacy Contact Number fallback, office matching, incomplete VRP fixture). Broader older integration suite also has failing expectations. No claim that the full repository suite passes.

Remaining limitation

Training list metadata is still scanned in Ruby for legacy fuzzy ownership rules. Heavy payload hydration and sorting work are bounded; candidate row count is not. Generic module lists and explicit all/export requests can still load full result sets. No production latency benchmark or deployment was performed.
