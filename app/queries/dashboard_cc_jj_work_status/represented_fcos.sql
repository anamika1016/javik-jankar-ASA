-- The detail report starts with visible farmers and only LEFT JOINs its
-- mapping/training details. Its represented FCOs therefore need no expansion
-- of target or training JSON arrays. Preserve the same scoped farmer filter.
SELECT DISTINCT a.fco_id
FROM public.afls a
WHERE %{list_fco_filter};
