# JJ latest log review — 5 October 2026

Project: `/home/papl/javik jankar ASA`.
Source: latest journalctl attachment. Routes below are matched by request ID;
neighboring completion lines must not be assigned to the latest Started line.

| Route | Samples | Min time (ms) | Max time (ms) | DB at slowest (ms) | Queries at slowest |
| --- | ---: | ---: | ---: | ---: | ---: |
| `/modules/stakeholder-master` | 2 | 87 | 1567 | 1522.7 | 5 |
| `/vrps/approvals` | 1 | 29752 | 29752 | 26645.6 | 9 |
| `/modules/gram-panchayat-master` | 2 | 32046 | 35477 | 22340.3 | 14 |
| `/target_mappings/vrp_mappings` | 10 | 33 | 4713 | 448.3 | 9 |
| `/modules/block-master` | 3 | 22746 | 37270 | 31977.2 | 13 |
| `/modules/village-master` | 2 | 98932 | 109865 | 73671.0 | 16 |
| `/modules/office-list` | 2 | 2515 | 4184 | 1760.6 | 5 |
| `/modules/lg-directory-list` | 2 | 10092 | 48492 | 40289.6 | 11 |
| `/vrps` | 1 | 41474 | 41474 | 40604.7 | 13 |
| `/dashboard` | 3 | 1980 | 2122 | 1462.0 | 77 |

The latest attachment does not show a 103-second stakeholder-master request:
its two complete samples take 87 ms and 1,567 ms. The approximately 99–110-second
requests are village-master; approximately 48 seconds is LG Directory, and
approximately 41 seconds is `/vrps`. Large variations and few queries on several
slow requests suggest that query count alone does not explain the delays.
Actual production query plans and wait statistics are not supplied.

## This follow-up

- Batch the six location catalogue reads into one ordered query. Keep all rows,
  aliases, JSON types and existing Ruby active/deleted filtering.
- Precompute immutable location alias keys instead of allocating the same key
  strings and array for every location row.
- Load gram-panchayat lookup data into lightweight rows instead of full Active
  Record instances. Existing ordering and matching rules are retained.
- Add a concurrent partial index on module slug and creation time using the exact
  existing SQL active/deleted predicates. This supports dropdown queries without
  changing their filters or response values.

No pagination, new shared caching, permission changes, approval rules, external
API fallback changes or data freshness changes were introduced.

## Validation

36 targeted tests / 133 assertions pass. Three existing dropdown tests / seven
assertions also pass: **39 tests, 140 assertions**, zero failures/errors.
`git diff --check` passes. Migration applied only to the local JJ test database.

Local read-only benchmark, five complete catalogue loads on the existing JJ
local dataset, excluding query caching:

| Metric | Original | Optimized |
| --- | ---: | ---: |
| Elapsed | 0.771 s | 0.484 s |
| Queries | 30 | 5 |
| Allocations | 2,688,748 | 2,244,612 |

This is approximately 37% less elapsed time and 17% fewer allocations for the
catalogue benchmark. It is not a production page benchmark, and does not prove
that the 30–110 second production requests have been resolved.

## Deployment and production diagnosis

Run `RAILS_ENV=production bundle exec rails db:migrate` during normal deployment.
No production deployment, restart or production data change was performed.

`PERFORMANCE_DIAGNOSTICS.sql` is a read-only script for a slow window. It captures
active database waits and blockers, database I/O/temporary-file counters, table
statistics and index use. Run it against the JJ production database using the
normal database access workflow. Compare snapshots during a slow request with
one from a quiet period. Cumulative counters alone do not establish a cause.

If requests remain slow, correlate these snapshots with the same request IDs
and server CPU/memory/disk measurements before changing server configuration.
