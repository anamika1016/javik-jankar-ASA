# JJ performance review — 5 October 2026

Project: `/home/papl/javik jankar ASA`.

## Log interpretation

Match requests by request ID. The supplied 232.7 and 248.0 second requests
are `/modules/training-form`; rendering dominates their duration. The logged
`send_bill_for_approval` calls take approximately 116–989 ms. The 246.9 second
completion has a different request ID whose start is absent from the excerpt;
it cannot be attributed to the adjacent approval request.

## Implemented changes

- Training mappings are built once per request and reused across the serialized
  form data and ICS, Gram, Main Activity and Sub Activity dropdowns. The existing
  farmer IDs, external farmer lookup, saved edit selections and completion
  payload remain present. Repeated external API work is avoided within a request.
- Other-target mappings and training/other-target month options are also reused.
- Location catalogue rows use `pluck(:id, :data)` and lightweight objects rather
  than full Active Record models. Existing location aliases, row order and active/
  deleted filtering are retained. The complete catalogue remains available.
- Approval-channel and approver dropdown queries execute once per request.
- JJ lookup indexes preserve exact ID priority and first-match precedence for
  names, usernames and phone numbers.
- Bill totals use the same target-progress computation but skip farmer display
  profiles, training display indexes and nested farmer detail rows that totals
  do not consume. Full bill/process/detail payloads remain unchanged.
- Payment passbooks are preloaded for the selected payment JJs, including blobs,
  removing per-row attachment queries.
- Concurrent indexes cover `(vrp_id, LOWER(BTRIM(month_name)))` and the JSON
  `bill_id` expression in bill approval history.

No shared cache, pagination, approval-rule changes or new business filtering
was introduced. The office list still reads its external API on each request;
changing its freshness or fallback rules would change behavior.

## Validation

Targeted suites: **34 tests, 125 assertions, zero failures/errors**:

```sh
PARALLEL_WORKERS=1 bundle exec rails test \
  test/controllers/module_lookup_performance_test.rb \
  test/controllers/jeevika_bill_invoice_test.rb \
  test/controllers/jeevika_bill_duplicate_guard_test.rb \
  test/controllers/user_hierarchy_list_test.rb \
  test/controllers/training_form_list_scope_test.rb \
  test/controllers/target_mapping_farmer_counts_test.rb
```

Tests compare legacy lookup precedence, location data types/filtering/order,
full versus lightweight bill summaries, and repeated query counts. The payment
passbook test checks three JJs twice with one attachment query.

Broader checks found four existing failures: one FCO-count expectation in
`module_read_performance_test.rb` and three training visibility expectations in
`training_form_visibility_test.rb`. All four reproduced with the original JJ
controller before these edits. They were not changed as part of this work.

`git diff --check` passes. Index migrations were applied to the local JJ test
DB only. The other `/home/papl/VRP` checkout is clean.

## Deployment and measurement

Apply during the normal JJ deployment:

```sh
RAILS_ENV=production bundle exec rails db:migrate
```

Production was not deployed or benchmarked. No end-to-end speedup numbers are
claimed for the listed pages. Compare identical users, filters and data volumes
before and after deployment using request duration, query count, DB duration,
GC time and response size. Large inline farmer/location JSON is retained to
preserve the existing interface; profile its rendering if it remains dominant.
