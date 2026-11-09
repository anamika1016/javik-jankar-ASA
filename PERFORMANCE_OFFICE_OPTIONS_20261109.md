# Office option read reuse

office_category_mappings and parent_office_mappings previously rebuilt their record-derived labels whenever a form/option helper asked again. Added request-local memoization with deep copies for callers. The original builder bodies, predicates, label fallbacks, ordering and uniqueness are unchanged. This avoids repeated model instantiation and reconstruction; caller mutations cannot leak to another read. No shared stale-data TTL was introduced.

New test compares complete mappings with the original builder output, observes zero model instantiations on repeated reads, mutates a returned string and confirms cache isolation, and verifies a new controller sees a persisted master update. Combined related regression run: 69 tests / 367 assertions, zero failures/errors. Diff check passed.

This is limited to repeated option reads, not proof of a production 16.78-second request fix. Training-edit global lookup deferral and village cache batching remain in the current patch. Previously documented broader suite failures remain unresolved. Production profiling/deployment/timing is still outstanding; not all listed delays are verified resolved.
