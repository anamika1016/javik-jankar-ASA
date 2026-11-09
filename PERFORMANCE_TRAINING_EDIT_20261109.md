# Current training edit bottleneck

Scanned 123 completed requests in the supplied 644646d1 log by request ID. Identifiable training edit requests include 83,174, 83,142, 82,036, 72,866, 70,134, 69,587 and 65,484 ms. Completion lines without starts were left unassigned rather than inferred from adjacent requests.

Found synchronous work in build_training_target_mappings: HTML edit forms resolved local/missing external farmer details across every available target before sending the HTML. Missing external names can fetch multiple villages/pages with 12-second read timeouts. The browser already requests farmers for selected targets through training_target_farmers, carrying record_id and saved farmer IDs.

HTML training edit rendering now defers the global farmer-details lookup to that existing selected-target endpoint, as new forms already did. Target metadata, mapped IDs, saved selected IDs and completion state remain in the form payload. Saved selections still use training_saved_farmers. This intentionally changes the initial HTML payload's farmer-detail arrays to empty; the visible details arrive through the existing asynchronous loader. JSON/API and non-edit reads retain full payloads. Save validation, permissions, endpoint output and approval rules were not edited.

Verification: edited render regression 1 test / 11 assertions; selected-target farmer/API checks 3 tests / 7 assertions; core training/revision/billing/approval regressions 51 tests / 269 assertions; two JavaScript test files passed. Diff check passed. Render regression raises if global local/external farmer lookups occur, retains saved IDs/completion state, and verifies JSON requests do not enter the deferred path.

The broader initial 76-test run had 2 failures / 3 errors in fixture/mock and dashboard-count tests. One separately rerun API compact-payload test also fails with a nil-request fixture. These were not changed or silently counted as passing; this review does not establish their baseline status. Focused checks above passed.

No production deployment or authenticated live timing performed. This removes a confirmed blocking call path; it does not establish the exact share of the logged 83-second duration or resolve every listed slow endpoint. Selected-farmer API latency can still depend on upstream responses.
