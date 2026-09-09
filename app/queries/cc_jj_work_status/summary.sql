WITH month_any_mapping AS (
    SELECT
        CASE LOWER(TRIM(t.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(t.fco_id) END AS fco_id,
        v.afl_id,
        STRING_AGG(DISTINCT t.vrp_id::text, ', ') AS vrp_ids
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
        STRING_AGG(DISTINCT t.vrp_id::text, ', ') AS training_vrp_ids
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

month_training_done AS (
    SELECT DISTINCT
        sf.farmer_id
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
),

/* FARMER KO USKE ACTUAL VRP + CC SE MAP KARNA */
farmer_vrp_mapping AS (
    SELECT DISTINCT
        CASE LOWER(TRIM(t.fco_id)) WHEN 'sausar' THEN '1004' WHEN 'turekela' THEN '1006' ELSE TRIM(t.fco_id) END AS fco_id,
        v.afl_id,
        t.vrp_id::text AS vrp_id,
        vd.vrp_name,
        vd.cluster_incharge
    FROM public.target_mappings t

    CROSS JOIN LATERAL jsonb_array_elements_text(
        t.afl_ids::jsonb
    ) AS v(afl_id)

    LEFT JOIN vrp_details vd
        ON vd.vrp_id = t.vrp_id::text

    WHERE %{target_month_filter}
      AND LOWER(COALESCE(t.main_activity_name, ''))
          LIKE '%farmers'' training%'
),

/* HAR FARMER KA STATUS */
farmer_status_data AS (
    SELECT DISTINCT
        fvm.fco_id,
        fvm.cluster_incharge,
        fvm.vrp_id,
        fvm.vrp_name,
        fvm.afl_id AS farmer_id,

        CASE
            WHEN td.farmer_id IS NOT NULL
                THEN 'Completed'
            ELSE 'Red'
        END AS farmer_status

    FROM farmer_vrp_mapping fvm

    LEFT JOIN month_training_done td
        ON td.farmer_id = fvm.afl_id

    WHERE %{summary_fco_filter}
),

/* 
   VRP FINAL STATUS:
   EK BHI FARMER RED HAI = VRP RED
   SAB COMPLETED HAIN = VRP COMPLETED
*/
vrp_final_status AS (
    SELECT
        fco_id,
        cluster_incharge,
        vrp_id,
        vrp_name,

        COUNT(DISTINCT farmer_id) AS total_farmer,

        COUNT(DISTINCT farmer_id)
            FILTER (
                WHERE farmer_status = 'Red'
            ) AS pending_farmer,

        COUNT(DISTINCT farmer_id)
            FILTER (
                WHERE farmer_status = 'Completed'
            ) AS completed_farmer,

        CASE
            WHEN COUNT(DISTINCT farmer_id)
                 FILTER (
                     WHERE farmer_status = 'Red'
                 ) > 0
            THEN 'Red'

            ELSE 'Completed'
        END AS final_status

    FROM farmer_status_data

    GROUP BY
        fco_id,
        cluster_incharge,
        vrp_id,
        vrp_name
),

/*
   CC FINAL STATUS:
   CC KE ANDAR EK BHI RED VRP HAI
   TO CC BHI RED
*/
cc_final_status AS (
    SELECT
        fco_id,
        cluster_incharge,

        CASE
            WHEN COUNT(*)
                 FILTER (
                     WHERE final_status = 'Red'
                 ) > 0
            THEN 'Red'

            ELSE 'Completed'
        END AS cc_status

    FROM vrp_final_status

    WHERE cluster_incharge IS NOT NULL

    GROUP BY
        fco_id,
        cluster_incharge
),

/* FCO SUMMARY */
fco_status_summary AS (
    SELECT
        v.fco_id,
        v.final_status,

        COUNT(DISTINCT v.vrp_id) AS vrp_count,

        COUNT(DISTINCT v.cluster_incharge)
            FILTER (
                WHERE c.cc_status = v.final_status
            ) AS cluster_incharge_count,

        SUM(v.total_farmer) AS total_farmer,

        SUM(v.pending_farmer) AS pending_farmer,

        SUM(v.completed_farmer) AS completed_farmer

    FROM vrp_final_status v

    LEFT JOIN cc_final_status c
        ON c.fco_id = v.fco_id
       AND c.cluster_incharge = v.cluster_incharge

    GROUP BY
        v.fco_id,
        v.final_status
)

SELECT
    %{month_label} AS month,
    fco_id,
    final_status AS status,

    cluster_incharge_count AS Toatl_CC,

    vrp_count AS Toatl_JJ,

    total_farmer AS Map_Farmer,

    pending_farmer  AS Red_Farmer,

    completed_farmer AS Green_Farmer

FROM fco_status_summary

ORDER BY
    fco_id,
    CASE
        WHEN final_status = 'Red' THEN 1
        WHEN final_status = 'Completed' THEN 2
        ELSE 3
    END;