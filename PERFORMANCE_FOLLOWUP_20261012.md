# Performance follow-up — 12 October 2026

## Latest journal evidence

Read all 356 lines of the latest uploaded journal. Matched Started/Processing/Completed entries by request UUID because requests overlap. The largest completed requests are:

| Route | Response | ActiveRecord | Queries |
| --- | ---: | ---: | ---: |
| `/vrps/new` | 199.207 s | 183.655 s | 31 |
| `/modules/training-form` | 136.576 s | 83.541 s | 29 |
| `/modules/jeevika-jankar-bill-list` | 134.405 s | 78.042 s | 31 |
| `/modules/jeevika-jankar-payment-list` | 106.725 s | 66.257 s | 33 |
| `/modules/other-target` | 103.918 s | 98.199 s | 16 |
| `/dashboard` | 99.228 s | 94.090 s | 90 |
| `/vrp-agreements` | 38.836 s | 36.978 s | 328 |
| `/modules/other-target-with-farmer` | 24.976 s | 18.945 s | 19 |

The quoted 199-second other-target-with-farmer and 328-query payment-list timings belonged to different overlapping requests. These figures are application instrumentation, not PostgreSQL execution plans; they do not identify a missing index or lock by themselves.

Login GET completed in 24–83 ms; login POST in 11 ms. Dashboard delay after redirect can make login feel slow. Three image blob redirects completed in 5, 16 and 72 ms; disk controller responses completed in 1 ms each. This does not measure browser download, transfer size or image decoding. No SQL statements or wait-event snapshots were present in this journal.

## Changes in this follow-up

- Accepted-agreement village resolution now preloads village IDs and fallback names in batches. Existing direct-ID, JSON alias, earliest-row, target-mapping, ICS-mapping, farmer-record and literal-name precedence is retained. Signature eligibility and user visibility filtering are unchanged. Direct detail lookups retain the existing resolver.
- Registration option readers reuse each module catalogue within one controller request. Original active filters, labels and ordering remain in place. No cross-request cache is introduced.
- Optional `PERFORMANCE_SQL_LOG_MS=1000` diagnostics log slow ActiveRecord operation duration and application source file/line. Disabled by default. SQL text, bind values and credentials are never emitted by this tracer. Duration can include process scheduling delays; PostgreSQL waits are still needed to establish the cause.

No new index migration is added without query-plan evidence. Earlier index migrations must be verified on the actual production database; their presence in the repository does not prove they have run there.

## Production read-only diagnostic capture

The production configuration supplied by the operator uses primary database `javik_jankar_asa_production`. While a slow request is running, execute from `/home/deploy/javik-jankar-ASA`:

```bash
sudo -u postgres psql -X -d javik_jankar_asa_production \
  -v ON_ERROR_STOP=1 < PERFORMANCE_DIAGNOSTICS.sql | tee performance_output.txt
```

This creates the previously missing output file and captures waits, blockers, table statistics, actual deployed index validity and migration versions. The script opens a read-only transaction with a five-second statement timeout. No production changes or deployment were performed from this workspace.

## Validation

The focused tests compare original and batched labels for 40 agreement rows, including repeated IDs, aliases, missing villages, literal labels and profile fallback. Batch village lookups are bounded at four SELECTs. Registration option readers execute one catalogue SELECT across three readers and preserve active filtering. Tracer tests verify private SQL literals cannot appear in diagnostic messages.

- Focused regression run: **33 tests, 160 assertions, zero failures/errors**. Includes agreement parity/query bounds, registration/CC/location, bill-read scaling, JJ reads and all-FCO participation. Leading-zero IDs and blank earliest aliases preserve original fallback behavior.
- Pagination JavaScript test: **1 passed, zero failed**.
- Full optimized run: **337 tests, 2,184 assertions, 19 failures, 6 errors**. The final additional alias edge case was subsequently covered by the focused run.
- Unchanged committed baseline from an isolated archive: **332 tests, 2,163 assertions, 19 failures, 6 errors**. Compared all 25 failure/error test names: identical sets, no introduced failures. The existing suite is therefore not fully green.
- `git diff --check` passed.

These are local regression results, not production latency measurements. Millisecond responses across all production APIs are not established until deployment and observation with representative production data and load.
