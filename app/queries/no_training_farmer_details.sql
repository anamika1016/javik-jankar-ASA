WITH august_any_mapping AS (
    SELECT
        t.fco_id,
        v.afl_id,

        STRING_AGG(
            DISTINCT t.vrp_id::text,
            ', '
        ) AS vrp_ids

    FROM public.target_mappings t

    CROSS JOIN LATERAL jsonb_array_elements_text(
        t.afl_ids::jsonb
    ) AS v(afl_id)

    WHERE %{target_month_filter}

    GROUP BY
        t.fco_id,
        v.afl_id
),

august_training_mapping AS (
    SELECT
        t.fco_id,
        v.afl_id,

        STRING_AGG(
            DISTINCT t.vrp_id::text,
            ', '
        ) AS training_vrp_ids

    FROM public.target_mappings t

    CROSS JOIN LATERAL jsonb_array_elements_text(
        t.afl_ids::jsonb
    ) AS v(afl_id)

    WHERE %{target_month_filter}
      AND LOWER(COALESCE(t.main_activity_name, ''))
          LIKE '%farmers'' training%'

    GROUP BY
        t.fco_id,
        v.afl_id
),


vrp_details AS (
    SELECT
        id::text AS vrp_id,
        name AS vrp_name,
        cluster_incharge
    FROM public.vrps
),


training_records AS MATERIALIZED (
    -- Extract record fields once, before expanding the selected farmer array.
    SELECT
        NULLIF(TRIM(mr.data::jsonb ->> 'main_activity_type'), '') AS main_activity_type,
        COALESCE(mr.data::jsonb -> 'selected_farmer_ids', '[]'::jsonb) AS farmer_ids
    FROM public.module_records mr
    WHERE mr.module_slug = 'training-form'
      AND %{entry_month_filter}
      AND LOWER(TRIM(COALESCE(mr.data::jsonb ->> 'main_activity', ''))) LIKE '%farmers'' training%'

),

august_training_done AS MATERIALIZED (
    SELECT sf.farmer_id,
        STRING_AGG(DISTINCT tr.main_activity_type, ', ') AS main_activity_type
    FROM training_records tr
    CROSS JOIN LATERAL jsonb_array_elements_text(tr.farmer_ids) AS sf(farmer_id)
    GROUP BY sf.farmer_id
),


farmer_vrp_details AS (
    SELECT
        am.fco_id,
        am.afl_id,

        STRING_AGG(
            DISTINCT vd.vrp_id,
            ', '
        ) AS vrp_id,

        STRING_AGG(
            DISTINCT vd.vrp_name,
            ', '
        ) AS vrp_name,

        STRING_AGG(
            DISTINCT vd.cluster_incharge,
            ', '
        ) AS cluster_incharge

    FROM august_any_mapping am

    CROSS JOIN LATERAL unnest(
        string_to_array(am.vrp_ids, ', ')
    ) AS x(vrp_id)

    LEFT JOIN vrp_details vd
        ON vd.vrp_id = x.vrp_id

    GROUP BY
        am.fco_id,
        am.afl_id
)

SELECT


    a.*,


    fvd.vrp_id,
    fvd.vrp_name,
    fvd.cluster_incharge,


    td.main_activity_type,


    CASE

        WHEN am.afl_id IS NULL
        THEN 'No Activity Mapping'

        WHEN am.afl_id IS NOT NULL
             AND tm.afl_id IS NULL
        THEN 'No Training Mapping'

        WHEN tm.afl_id IS NOT NULL
             AND td.farmer_id IS NULL
        THEN 'Training Mapped But No Entry'

        WHEN td.farmer_id IS NOT NULL
        THEN 'Training Entry Done'

        ELSE 'Other'

    END AS status,


    CASE
        WHEN am.afl_id IS NOT NULL
        THEN 'Yes'
        ELSE 'No'
    END AS activity_mapped,


    CASE
        WHEN tm.afl_id IS NOT NULL
        THEN 'Yes'
        ELSE 'No'
    END AS training_mapped,


    CASE
        WHEN td.farmer_id IS NOT NULL
        THEN 'Yes'
        ELSE 'No'
    END AS training_entry_done,


    CASE
        WHEN td.farmer_id IS NULL
        THEN 'Red'
        ELSE 'Completed'
    END AS farmer_status

FROM public.afls a

LEFT JOIN august_any_mapping am
    ON am.fco_id = a.fco_id
   AND am.afl_id = a.id::text

LEFT JOIN august_training_mapping tm
    ON tm.fco_id = a.fco_id
   AND tm.afl_id = a.id::text

LEFT JOIN august_training_done td
    ON td.farmer_id = a.id::text

LEFT JOIN farmer_vrp_details fvd
    ON fvd.fco_id = a.fco_id
   AND fvd.afl_id = a.id::text

WHERE a.fco_id IN (:fco_ids) AND a.id IN (:visible_farmer_ids)
  AND td.farmer_id IS NULL

ORDER BY
    a.fco_id,
    fvd.vrp_name,
    a.id;
