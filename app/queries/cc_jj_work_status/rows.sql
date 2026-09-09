WITH month_any_mapping AS (
    SELECT
        CASE LOWER(TRIM(t.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(t.fco_id) END AS fco_id,
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
        CASE LOWER(TRIM(t.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(t.fco_id) END,
        v.afl_id
),

month_training_mapping AS (
    SELECT
        CASE LOWER(TRIM(t.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(t.fco_id) END AS fco_id,
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
        CASE LOWER(TRIM(t.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(t.fco_id) END,
        v.afl_id
),

vrp_details AS (
    SELECT
        id::text AS vrp_id,
        name AS vrp_name,
        cluster_incharge
    FROM public.vrps
),

/* ONLY AUGUST FARMERS' TRAINING ENTRY */
month_training_done AS (
    SELECT
        sf.farmer_id,

        STRING_AGG(
            DISTINCT NULLIF(
                TRIM(mr.data::jsonb ->> 'main_activity_type'),
                ''
            ),
            ', '
        ) AS main_activity_type,

        /* CLUSTER COORDINATOR NAME */
        STRING_AGG(
            DISTINCT NULLIF(
                TRIM(mr.data::jsonb ->> 'cluster_coordinator_name'),
                ''
            ),
            ', '
        ) AS cluster_coordinator_name,

        /* AGRONOMIST NAME */
        STRING_AGG(
            DISTINCT NULLIF(
                TRIM(mr.data::jsonb ->> 'agronomist_name'),
                ''
            ),
            ', '
        ) AS agronomist_name

    FROM public.module_records mr

    CROSS JOIN LATERAL jsonb_array_elements_text(
        COALESCE(
            mr.data::jsonb -> 'selected_farmer_ids',
            '[]'::jsonb
        )
    ) AS sf(farmer_id)

    WHERE mr.module_slug = 'training-form'

      AND %{entry_month_filter}

      AND LOWER(
            TRIM(
                COALESCE(
                    mr.data::jsonb ->> 'main_activity',
                    ''
                )
            )
          ) LIKE '%farmers'' training%'

    GROUP BY
        sf.farmer_id
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

    FROM month_any_mapping am

    CROSS JOIN LATERAL unnest(
        string_to_array(am.vrp_ids, ', ')
    ) AS x(vrp_id)

    LEFT JOIN vrp_details vd
        ON vd.vrp_id = x.vrp_id

    GROUP BY
        am.fco_id,
        am.afl_id
),

registered_farmer_vrp_details AS (
    SELECT
        CASE LOWER(TRIM(m.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(m.fco_id) END AS fco_id,
        farmer.afl_id,
        STRING_AGG(DISTINCT NULLIF(TRIM(v.name), ''), ', ') AS vrp_name,
        STRING_AGG(DISTINCT NULLIF(TRIM(v.cluster_incharge), ''), ', ') AS cluster_incharge
    FROM public.vrp_ics_mappings m
    JOIN public.vrps v ON v.id = m.vrp_id
    CROSS JOIN LATERAL jsonb_array_elements_text(m.afl_ids::jsonb) farmer(afl_id)
    WHERE %{assignment_visibility_filter}
    GROUP BY 1, 2
),

base_farmer_data AS (
    SELECT
        a.id::text AS farmer_id,

        %{month_label} AS month,

        a.fco_id,
        a.fpo_id,
        a.fpo_name,

        CASE WHEN fvd.vrp_id IS NOT NULL THEN fvd.cluster_incharge ELSE registered.cluster_incharge END AS cluster_incharge,
        CASE WHEN fvd.vrp_id IS NOT NULL THEN fvd.vrp_name ELSE registered.vrp_name END AS vrp_name,

        td.main_activity_type,

        td.cluster_coordinator_name,
        td.agronomist_name,

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
            WHEN tm.afl_id IS NOT NULL
                 AND td.farmer_id IS NULL
            THEN 'Red'

            WHEN td.farmer_id IS NOT NULL
            THEN 'Completed'

            ELSE NULL
        END AS farmer_status

    FROM public.afls a

    LEFT JOIN month_any_mapping am
        ON am.fco_id = a.fco_id
       AND am.afl_id = a.id::text

    LEFT JOIN month_training_mapping tm
        ON tm.fco_id = a.fco_id
       AND tm.afl_id = a.id::text

    LEFT JOIN month_training_done td
        ON td.farmer_id = a.id::text

    LEFT JOIN farmer_vrp_details fvd
        ON fvd.fco_id = a.fco_id
       AND fvd.afl_id = a.id::text

    LEFT JOIN registered_farmer_vrp_details registered
        ON registered.fco_id = a.fco_id AND registered.afl_id = a.id::text

    WHERE %{list_fco_filter}
)

SELECT
    month,
    fco_id,
    fpo_id,
    fpo_name,
    cluster_incharge,
    vrp_name,

    /* TOTAL FARMER */
    COUNT(DISTINCT farmer_id) AS total_farmer,

    /* STATUS WISE */
    COUNT(DISTINCT farmer_id) FILTER (
        WHERE status = 'No Activity Mapping'
    ) AS "No Activity Mapping",

    COUNT(DISTINCT farmer_id) FILTER (
        WHERE status = 'No Training Mapping'
    ) AS "No Training Mapping",

    COUNT(DISTINCT farmer_id) FILTER (
        WHERE status = 'Training Mapped But No Entry'
    ) AS "Training Mapped But No Entry",

    COUNT(DISTINCT farmer_id) FILTER (
        WHERE status = 'Training Entry Done'
    ) AS "Training Entry Done",

    /* FARMER STATUS */
    COUNT(DISTINCT farmer_id) FILTER (
        WHERE farmer_status = 'Red'
    ) AS "Red",

    COUNT(DISTINCT farmer_id) FILTER (
        WHERE farmer_status = 'Completed'
    ) AS "Completed",

    /* CLUSTER COORDINATOR INVOLVEMENT */
    COUNT(DISTINCT farmer_id) FILTER (
        WHERE status = 'Training Entry Done'
          AND NULLIF(
                TRIM(COALESCE(cluster_coordinator_name, '')),
                ''
              ) IS NOT NULL
    ) AS "Cluster Coordinator Involved",

    /* AGRONOMIST INVOLVEMENT */
    COUNT(DISTINCT farmer_id) FILTER (
        WHERE status = 'Training Entry Done'
          AND NULLIF(
                TRIM(COALESCE(agronomist_name, '')),
                ''
              ) IS NOT NULL
    ) AS "Agronomist Involved"

FROM base_farmer_data

GROUP BY
    month,
    fco_id,
    fpo_id,
    fpo_name,
    cluster_incharge,
    vrp_name

ORDER BY
    cluster_incharge,
    vrp_name;