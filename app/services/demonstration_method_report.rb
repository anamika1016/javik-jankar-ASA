# Uses the same target population for both the FCO summary and VRP drill-down.
class DemonstrationMethodReport
  HEADERS = ["fco_id", "fco_name", "vrp_id", "VRP Name", "OPG Target", "General Training/Meeting", "Input Demo INM", "Input Demo PM", "FFS"].freeze
  METRICS = HEADERS.drop(4).freeze

  def initialize(targets:, month: "August")
    @target_ids = Array(targets).map(&:id).uniq
    @month = month.to_s.strip.downcase
  end

  def rows
    @rows ||= begin
      connection = TargetMapping.connection
      scope = TargetMapping.where(id: @target_ids)
      scope = scope.where("LOWER(TRIM(month_name)) = ?", @month) unless @month.blank? || @month == "all"
      month_filter = if @month.blank? || @month == "all"
        "TRUE"
      else
        "LOWER(TRIM(mr.data::jsonb ->> 'month')) = #{connection.quote(@month)}"
      end
      connection.select_all(<<~SQL).to_a
        WITH target_data AS (
          SELECT t.fco_id, t.fco_name, t.vrp_id,
                 SUM(COALESCE(t.opg_training_target, 0)) AS opg_training_target
          FROM (#{scope.to_sql}) t
          GROUP BY t.fco_id, t.fco_name, t.vrp_id
        ), entry_data AS (
          SELECT (mr.data::jsonb ->> 'created_by_id') AS vrp_id,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'general training/meeting') AS general_training_meeting,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo inm') AS input_demo_inm,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo pm') AS input_demo_pm,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'ffs') AS ffs
          FROM module_records mr
          WHERE mr.module_slug = 'training-form' AND #{month_filter}
            AND (mr.data::jsonb ->> 'created_by_id') IN (SELECT vrp_id::text FROM target_data)
          GROUP BY (mr.data::jsonb ->> 'created_by_id')
        )
        SELECT t.fco_id, t.fco_name, t.vrp_id, v.name AS "VRP Name",
          t.opg_training_target AS "OPG Target",
          COALESCE(e.general_training_meeting, 0) AS "General Training/Meeting",
          COALESCE(e.input_demo_inm, 0) AS "Input Demo INM",
          COALESCE(e.input_demo_pm, 0) AS "Input Demo PM",
          COALESCE(e.ffs, 0) AS "FFS"
        FROM target_data t
        LEFT JOIN vrps v ON v.id::text = t.vrp_id::text
        LEFT JOIN entry_data e ON e.vrp_id = t.vrp_id::text
        ORDER BY t.fco_id, v.name
      SQL
    end
  end

  def summary
    @summary ||= begin
      connection = TargetMapping.connection
      scope = TargetMapping.where(id: @target_ids)
      scope = scope.where("LOWER(TRIM(month_name)) = ?", @month) unless @month.blank? || @month == "all"
      month_filter = @month.blank? || @month == "all" ? "TRUE" : "LOWER(TRIM(mr.data::jsonb ->> 'month')) = #{connection.quote(@month)}"
      connection.select_all(<<~SQL).to_a
        WITH vrp_target AS (
          SELECT t.fco_id, t.fco_name, t.vrp_id,
            SUM(COALESCE(t.opg_training_target, 0)) AS opg_training_target
          FROM (#{scope.to_sql}) t
          GROUP BY t.fco_id, t.fco_name, t.vrp_id
        ), fco_target AS (
          SELECT fco_id, fco_name, SUM(opg_training_target) AS opg_training_target
          FROM vrp_target GROUP BY fco_id, fco_name
        ), entry_data AS (
          SELECT vt.fco_id, vt.fco_name,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'general training/meeting') AS general_training_meeting,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo inm') AS input_demo_inm,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo pm') AS input_demo_pm,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'ffs') AS ffs
          FROM module_records mr
          INNER JOIN (SELECT DISTINCT fco_id, fco_name, vrp_id FROM vrp_target) vt
            ON vt.vrp_id::text = TRIM(mr.data::jsonb ->> 'created_by_id')
          WHERE mr.module_slug = 'training-form' AND #{month_filter}
          GROUP BY vt.fco_id, vt.fco_name
        )
        SELECT ft.fco_id, ft.fco_name, ft.opg_training_target AS "OPG Target",
          COALESCE(ed.general_training_meeting, 0) AS "General Training/Meeting",
          COALESCE(ed.input_demo_inm, 0) AS "Input Demo INM",
          COALESCE(ed.input_demo_pm, 0) AS "Input Demo PM",
          COALESCE(ed.ffs, 0) AS "FFS"
        FROM fco_target ft
        LEFT JOIN entry_data ed ON ed.fco_id::text = ft.fco_id::text
        ORDER BY ft.fco_id
      SQL
    end
  end
end
