# Uses the same target population for both the FCO summary and VRP drill-down.
class DashboardDemonstrationMethodReport
  # View List (per-JJ drill-down) columns. Each training method has a record Count
  # and a distinct Farmer count; "Target Farmer Count" is village-deduped per JJ.
  HEADERS = [
    "fco_id", "fco_name", "Cluster Coordinator", "vrp_id", "VRP Name",
    "OPG Target / Done", "General Training/Meeting", "Input Demo INM",
    "Input Demo PM", "FFS", "CC TARGET STATUS", "Status"
  ].freeze

  METRICS = ["OPG Target", "General Training/Meeting", "Input Demo INM", "Input Demo PM", "FFS", "CC TARGET STATUS"].freeze

  # Excel export: each metric split into separate Target and Achievement columns
  # (instead of the combined "target / done" cell shown in the on-screen list).
  EXPORT_HEADERS = [
    "fco_id", "fco_name", "Cluster Coordinator", "vrp_id", "VRP Name",
    "OPG Target", "OPG Achievement",
    "General Training/Meeting Target", "General Training/Meeting Achievement",
    "Input Demo INM Target", "Input Demo INM Achievement",
    "Input Demo PM Target", "Input Demo PM Achievement",
    "FFS Target", "FFS Achievement",
    "CC Target", "CC Achievement",
    "Status"
  ].freeze

  def initialize(targets:, month: "August")
    if targets.is_a?(ActiveRecord::Relation) && !targets.loaded?
      @target_ids = targets.pluck(:id).uniq
      @fco_ids = nil
    else
      list = Array(targets)
      @target_ids = list.map(&:id).uniq
      # Targets are already in memory — read their FCO ids here instead of
      # firing another WHERE id IN (...) query with a huge id list later.
      @fco_ids = list.filter_map { |t| t.fco_id if t.respond_to?(:fco_id) }
        .map(&:to_s).reject(&:blank?).uniq.presence
    end
    @month = month.to_s.strip.downcase
  end

  def rows
    @rows ||= begin
      connection = TargetMapping.connection
      scope = demonstration_target_scope
      scope = scope.where("LOWER(TRIM(month_name)) = ?", @month) unless @month.blank? || @month == "all"
      month_filter = if @month.blank? || @month == "all"
        "TRUE"
      else
        "LOWER(TRIM(mr.data::jsonb ->> 'month')) = #{connection.quote(@month)}"
      end
      raw_rows = connection.select_all(<<~SQL).to_a
        WITH scoped_targets AS (
          #{scope.to_sql}
        ), village_target AS (
          SELECT
            t.fco_id, t.fco_name, t.vrp_id, t.village_id, t.month_name,
            MAX(COALESCE(t.opg_training_target, 0)) AS opg_training_target,
            MAX(COALESCE(t.week_wise_opg_target, 0)) AS general_training_target,
            MAX(COALESCE(t.input_demo_inm_target, 0)) AS input_demo_inm_target,
            MAX(COALESCE(t.input_demo_pm_target, 0)) AS input_demo_pm_target,
            MAX(COALESCE(t.ffs_target, 0)) AS ffs_target,
            MAX(COALESCE(t.cc_target, 0)) AS cc_target
          FROM scoped_targets t
          GROUP BY t.fco_id, t.fco_name, t.vrp_id, t.village_id, t.month_name
        ), vrp_target AS (
          SELECT
            fco_id, fco_name, vrp_id,
            SUM(opg_training_target) AS opg_training_target,
            SUM(general_training_target) AS general_training_target,
            SUM(input_demo_inm_target) AS input_demo_inm_target,
            SUM(input_demo_pm_target) AS input_demo_pm_target,
            SUM(ffs_target) AS ffs_target,
            SUM(cc_target) AS cc_target
          FROM village_target
          GROUP BY fco_id, fco_name, vrp_id
        ), entry_data AS (
          SELECT
            #{record_vrp_id_sql} AS vrp_id,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'general training/meeting') AS general_training_done,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo inm') AS input_demo_inm_done,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo pm') AS input_demo_pm_done,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'ffs') AS ffs_done,
            -- CC achievement only counts sessions that still name a Cluster
            -- Coordinator. Clearing the field, or picking "N/A", must drop the
            -- session from the CC total while leaving the per-method counts
            -- above untouched -- the training still happened. Records saved
            -- before the field existed have no key at all and still count.
            COUNT(*) FILTER (
              WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method'))
                      IN ('general training/meeting', 'input demo inm', 'input demo pm', 'ffs')
                AND NOT (
                  (mr.data::jsonb ? 'cluster_coordinator_name')
                  AND COALESCE(TRIM(mr.data::jsonb ->> 'cluster_coordinator_name'), '') ~* '^(|n\\.?/?a\\.?|none|nil|null|-+)$'
                )
            ) AS cc_done
          FROM module_records mr
          WHERE mr.module_slug = 'training-form' AND #{month_filter}
            -- Only in-scope JJ records; the final LEFT JOIN discards the rest anyway,
            -- so results are identical but the scan/group is far smaller.
            AND #{record_vrp_id_sql} IN (
              SELECT DISTINCT vt.vrp_id::text FROM vrp_target vt
            )
          GROUP BY #{record_vrp_id_sql}
        )
        SELECT
          vt.fco_id, vt.fco_name,
          COALESCE(v.cluster_incharge, '') AS "Cluster Coordinator",
          vt.vrp_id,
          COALESCE(v.name, '') AS "VRP Name",
          vt.opg_training_target AS opg_target,
          vt.general_training_target AS gen_target,
          COALESCE(ed.general_training_done, 0) AS gen_done,
          vt.input_demo_inm_target AS inm_target,
          COALESCE(ed.input_demo_inm_done, 0) AS inm_done,
          vt.input_demo_pm_target AS pm_target,
          COALESCE(ed.input_demo_pm_done, 0) AS pm_done,
          vt.ffs_target AS ffs_target,
          COALESCE(ed.ffs_done, 0) AS ffs_done,
          COALESCE(vt.cc_target, 0) AS cc_target,
          COALESCE(ed.cc_done, 0) AS cc_done
        FROM vrp_target vt
        LEFT JOIN vrps v ON v.id::text = vt.vrp_id::text
        LEFT JOIN entry_data ed ON ed.vrp_id = vt.vrp_id::text
        ORDER BY vt.fco_id, "Cluster Coordinator", vt.vrp_id
      SQL

      raw_rows.map do |r|
        gen_t = r["gen_target"].to_i
        gen_d = r["gen_done"].to_i
        inm_t = r["inm_target"].to_i
        inm_d = r["inm_done"].to_i
        pm_t  = r["pm_target"].to_i
        pm_d  = r["pm_done"].to_i
        ffs_t = r["ffs_target"].to_i
        ffs_d = r["ffs_done"].to_i
        cc_t  = r["cc_target"].to_i
        cc_d  = r["cc_done"].to_i
        # A training session is not a CC achievement unless a CC target was
        # assigned to this JJ. This prevents FCOs/JJs with a zero target from
        # displaying unrelated training entries as CC achievement.
        cc_d = 0 unless cc_t.positive?

        tot_t = r["opg_target"].to_i
        tot_d = gen_d + inm_d + pm_d + ffs_d

        status = if tot_t.positive? && tot_d.zero?
          "Red"
        elsif tot_t.positive? && tot_d > 0 && tot_d < tot_t
          "Yellow"
        else
          "Green"
        end

        {
          "fco_id"                  => r["fco_id"],
          "fco_name"                => r["fco_name"],
          "Cluster Coordinator"     => r["Cluster Coordinator"],
          "vrp_id"                  => r["vrp_id"],
          "VRP Name"                => r["VRP Name"],
          "OPG Target / Done"       => "#{tot_t} / #{tot_d}",
          "General Training/Meeting"=> "#{gen_t} / #{gen_d}",
          "Input Demo INM"          => "#{inm_t} / #{inm_d}",
          "Input Demo PM"           => "#{pm_t} / #{pm_d}",
          "FFS"                     => "#{ffs_t} / #{ffs_d}",
          "CC TARGET STATUS"        => "#{cc_t} / #{cc_d}",
          "Status"                  => status,
          # Split numeric values used by the Excel export (EXPORT_HEADERS).
          "OPG Target"              => tot_t,
          "OPG Achievement"         => tot_d,
          "General Training/Meeting Target"      => gen_t,
          "General Training/Meeting Achievement" => gen_d,
          "Input Demo INM Target"       => inm_t,
          "Input Demo INM Achievement"  => inm_d,
          "Input Demo PM Target"        => pm_t,
          "Input Demo PM Achievement"   => pm_d,
          "FFS Target"                  => ffs_t,
          "FFS Achievement"             => ffs_d,
          "CC Target"                   => cc_t,
          "CC Achievement"              => cc_d
        }
      end
    end
  end

  def summary
    @summary ||= begin
      connection = TargetMapping.connection
      scope = demonstration_target_scope
      scope = scope.where("LOWER(TRIM(month_name)) = ?", @month) unless @month.blank? || @month == "all"
      month_filter = @month.blank? || @month == "all" ? "TRUE" : "LOWER(TRIM(mr.data::jsonb ->> 'month')) = #{connection.quote(@month)}"
      connection.select_all(<<~SQL).to_a
        WITH scoped_targets AS (
          #{scope.to_sql}
        ), village_target AS (
          SELECT t.fco_id, t.fco_name, t.village_id, t.month_name,
            MAX(COALESCE(t.opg_training_target, 0)) AS opg_training_target,
            MAX(COALESCE(t.week_wise_opg_target, 0)) AS general_training_target,
            MAX(COALESCE(t.input_demo_inm_target, 0)) AS input_demo_inm_target,
            MAX(COALESCE(t.input_demo_pm_target, 0)) AS input_demo_pm_target,
            MAX(COALESCE(t.ffs_target, 0)) AS ffs_target,
            MAX(COALESCE(t.cc_target, 0)) AS cc_target
          FROM scoped_targets t
          GROUP BY t.fco_id, t.fco_name, t.village_id, t.month_name
        ), fco_target AS (
          SELECT fco_id, fco_name,
            SUM(opg_training_target) AS opg_training_target,
            SUM(general_training_target) AS general_training_target,
            SUM(input_demo_inm_target) AS input_demo_inm_target,
            SUM(input_demo_pm_target) AS input_demo_pm_target,
            SUM(ffs_target) AS ffs_target,
            SUM(cc_target) AS cc_target
          FROM village_target GROUP BY fco_id, fco_name
        ), vrp_fco AS (
          SELECT DISTINCT t.fco_id, t.fco_name, t.vrp_id
          FROM scoped_targets t
        ), entry_data AS (
          SELECT vf.fco_id, vf.fco_name,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'general training/meeting') AS general_training_meeting,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo inm') AS input_demo_inm,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'input demo pm') AS input_demo_pm,
            COUNT(*) FILTER (WHERE LOWER(TRIM(mr.data::jsonb ->> 'training_method')) = 'ffs') AS ffs
          FROM module_records mr
          INNER JOIN vrp_fco vf ON vf.vrp_id::text = #{record_vrp_id_sql}
          WHERE mr.module_slug = 'training-form' AND #{month_filter}
          GROUP BY vf.fco_id, vf.fco_name
        )
        SELECT ft.fco_id, ft.fco_name,
          ft.opg_training_target AS "OPG Target",
          ft.cc_target AS "CC Target",
          ft.general_training_target AS "General Training/Meeting Target",
          COALESCE(ed.general_training_meeting, 0) AS "General Training/Meeting",
          COALESCE(ed.general_training_meeting, 0) AS "General Training/Meeting Done",
          ft.input_demo_inm_target AS "Input Demo INM Target",
          COALESCE(ed.input_demo_inm, 0) AS "Input Demo INM",
          COALESCE(ed.input_demo_inm, 0) AS "Input Demo INM Done",
          ft.input_demo_pm_target AS "Input Demo PM Target",
          COALESCE(ed.input_demo_pm, 0) AS "Input Demo PM",
          COALESCE(ed.input_demo_pm, 0) AS "Input Demo PM Done",
          ft.ffs_target AS "FFS Target",
          COALESCE(ed.ffs, 0) AS "FFS",
          COALESCE(ed.ffs, 0) AS "FFS Done"
        FROM fco_target ft
        LEFT JOIN entry_data ed ON ed.fco_id::text = ft.fco_id::text
        ORDER BY ft.fco_id
      SQL
    end
  end

  private

  def record_vrp_id_sql
    <<~SQL.squish
      COALESCE(NULLIF(TRIM(mr.data::jsonb ->> 'jeevika_jankar_id'), ''),
        NULLIF(TRIM(mr.data::jsonb ->> 'vrp_id'), ''),
        NULLIF(TRIM(mr.data::jsonb ->> 'select_vrp'), ''),
        CASE WHEN COALESCE(mr.data::jsonb ->> 'created_by_record_type', '') IN ('', 'Vrp')
          THEN NULLIF(TRIM(mr.data::jsonb ->> 'created_by_id'), '') END)
    SQL
  end

  # Preserve the selected FCO(s), but use every mapping in those FCOs for the
  # month. This is the same population as the supplied FCO-wise SQL query.
  def demonstration_target_scope
    # Preserve the caller's JJ/month/activity scope, including an empty scope.
    # Expanding to the whole FCO reintroduces unrelated CC achievements.
    TargetMapping.where(id: @target_ids)
  end
end
