# Dashboard summary and farmer participation fix

Reference project: `/home/papl/VRP/app/controllers/modules_controller.rb`.
Application dashboard route: `DashboardReportsController#dashboard`.

Compared the reference methods individually: `dashboard_summary_query_counts`, `farmer_training_mapped_farmer_count_and_popups`, `compute_farmer_training_no_training_count_and_popups`, and `farmer_training_attendance_counts_by_fco`. The existing app's SQL already uses the VRP mapped-farmer expansion and distinct training-entry classification. The reproduced failure was the farmer population filter, rather than the yellow/green arithmetic.

| Box | VRP query definition retained |
| --- | --- |
| Mapped Farmer | Distinct nonblank farmer IDs expanded from matching target mappings' `afl_ids` |
| Pending | Authorized farmer-master population without matching training attendance in the selected month |
| Only 1 Training | `COUNT(DISTINCT training_id) = 1`, counting each farmer once |
| 1+ Trainings | `COUNT(DISTINCT training_id) > 1`, counting each farmer once |
| Summary farmer count | Count populated tracenet numbers in the authorized, selected-office farmer scope |
| Summary ICS/villages | The existing VRP grouping by FCO/FPO/ICS/village fields; not converted to a different distinct-count rule |

The reference also scopes office staff using office ID **or** office name. The current dashboard had regressed to exact `fco_id IN (...)` filters for both staff population and selected-office summaries. IDs were normalized by the office directory but not on the stored farmer rows; blank or spaced IDs and legacy name spellings could yield an empty population, even when target mappings were populated.

Changed the shared dashboard FCO predicate to compare trimmed IDs, saved aliases and normalized office names (`FCO-Bhawanipatna`, `FCO - Bhawanipatna`, `Bhawanipatna`, etc.). Staff visibility and selected-office summaries now use this same predicate. Existing JJ/cluster restrictions and ICS filters still apply before selected filters. Selecting a different office does not widen a staff user's scope. Boxes and View List queries share the predicate, avoiding a count/list mismatch.

Incremented participation cache namespaces to v7 (agronomist namespace v2), so previous cached zero populations are not reused. No data migration, record rewrite, JavaScript edit, payment change or global cache clear is included.

## Reproduction and validation

The new regression fixture uses four Bhawanipatna farmers with blank/spaced legacy IDs, a different target-office ID, duplicate selected farmer IDs in a training entry, and an outside-office farmer.

- Before the fix, the summary scope returned **zero farmers** instead of four; the reproduction test failed.
- After the fix, actual admin and staff login requests render **Mapped 4, Pending 1, Only 1 Training 2, 1+ Trainings 1**, and summary farmer count **4**.
- Each participation View List matches its card's unique farmer count.
- All-month lists retain those counts; a month without training has **Pending 4, Yellow 0, Green 0**.
- A staff login selecting an outside office gets an empty population rather than outside-office data.
- Focused dashboard/reference/participation/FCO tests: **43 tests, 372 assertions, zero failures/errors**, including the final guard preventing a missing-office placeholder from authorizing unassigned farmer data.
- Full regression: **346 tests, 2,260 assertions, 19 failures and 6 errors**. All 25 failure/error names match the previous baseline; no new failures. The final additional placeholder guard was then verified in the focused run.
- `git diff --check` passed.

These are isolated local test results. The production database and screenshot's actual 2,059 mapped farmers were not queried, and no deployment was performed. The reproduced bug is corrected, but production counts must be checked after deploying against the actual source data.
