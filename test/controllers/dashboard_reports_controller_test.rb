require "test_helper"

class DashboardReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "report_admin", password: "secret", first_name: "Admin", user_type: "admin", status: "Active")
    @staff = User.create!(user_name: "report_agro", password: "secret", first_name: "Office", role: "Agronomist", office_name: "FCO-Bhawanipatna", user_type: "User", status: "Active")
    @cc = User.create!(user_name: "report_cc", password: "secret", first_name: "Assigned", last_name: "CC", role: "Cluster Incharge", office_name: "FCO-Bhawanipatna", user_type: "User", status: "Active")
    ModuleRecord.create!(module_slug: "access-control", data: { "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active" })
    @mine = create_vrp("Office JJ", "FCO-C Bhawanipatna", "Assigned CC (Cluster Incharge)")
    @same_office = create_vrp("Other CC JJ", "FCO-C Bhawanipatna", "Other CC (Cluster Incharge)")
    @other = create_vrp("Outside JJ", "FCO-C New Office", "Other CC (Cluster Incharge)")
    @farmer = Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "ics-a", ics_name: "ICS A", village_id: "v-a", village_name: "Village A", tracenet_no: "FARMER-A", farmer_name: "Assigned Farmer")
    @outside_farmer = Afl.create!(fco_id: "9999", fco: "New Office", ics_id: "ics-b", ics_name: "ICS B", village_id: "v-b", village_name: "Village B", tracenet_no: "FARMER-B", farmer_name: "Outside Farmer")
    @target = create_target(@mine, @farmer, "September", "Soil Preparation")
    create_target(@other, @outside_farmer, "October", "Outside Indicator")
    ModuleRecord.create!(module_slug: "other-target", data: {
      "jeevika_jankar_id" => @mine.id.to_s, "jeevika_jankar_name" => @mine.name,
      "fcoc_name" => @mine.fcoc, "month" => "September", "ics" => "ICS A",
      "training_topic" => "Legacy Main", "training_subject" => "Legacy Sub",
      "target" => "10", "achievement" => "4", "status" => "Active"
    })
  end

  test "sub indicator options remain discoverable without current-month targets" do
    login(@staff)
    get dashboard_path
    assert_response :success
    assert_select "#dash_sub_activity option", text: "Soil Preparation"
    assert_select "#dash_fcoc option[selected]", text: "Bhawanipatna"
    assert_select "#dash_fcoc option", text: "Bhawanipatna", count: 1
  end

  test "ICS master and CC JJ boxes render outside training activity mode" do
    Afl.create!(farmer_name: "Unassigned", fco_id: "995", fco: "FCO-C Bhawanipatna", ics_name: "ICS Without Target")
    login(@admin)
    get dashboard_path, params: { month: "", main_activity: "Other Work" }
    assert_response :success
    assert_select "#dash_ics option", text: "ICS Without Target"
    assert_select "#other_major_work_indicator_boxes", text: /Main Major Work Indicator - Other/
    assert_select ".cc-jj-work-status", text: /CC and JJ Work Status/
    assert_select ".cc-jj-status-fco-name", text: "Bhawanipatna"
  end

  test "admin all-month mapped count and list include months beyond August" do
    c = calculator(@admin)
    count, = c.send(:farmer_training_mapped_farmer_count_and_popups, month_name: nil, fcoc_name: nil)
    rows = c.send(:farmer_training_participation_rows_from_sql, "mapped", month_name: nil, fcoc_name: nil)
    assert_equal 2, count
    assert_equal count, rows.size
    assert_equal [@farmer.id.to_s, @outside_farmer.id.to_s].sort, rows.map { |row| row[:farmer_id] }.sort
  end

  test "participation cache separates cluster filters for the same admin" do
    first = calculator(@admin)
    first.params = ActionController::Parameters.new(month: "", cluster_incharge: "Assigned CC")
    second = calculator(@admin)
    second.params = ActionController::Parameters.new(month: "", cluster_incharge: "Other CC")
    first_key = first.send(:training_participation_dashboard_counts_cache_key, month_name: nil, fcoc_name: nil)
    second_key = second.send(:training_participation_dashboard_counts_cache_key, month_name: nil, fcoc_name: nil)
    assert_not_nil first_key
    assert_not_equal first_key, second_key
  end

  test "mapped training API uses the same office and assigned JJ scope" do
    payload = ->(user) { { "id" => user.id, "record_type" => "User", "user_type" => user.user_type, "name" => user.full_name, "role" => user.role, "office_name" => user.office_name } }
    [@staff, @cc].each do |user|
      api = FarmerTargetApi.new(current_app_user: payload.call(user), module_slug: "training-form")
      assert_equal [@farmer.id.to_s], api.training_mappings.flat_map { |mapping| mapping[:farmers].map { |farmer| farmer[:id] } }.uniq
      forged = FarmerTargetApi.new(current_app_user: payload.call(user), module_slug: "training-form")
      assert_empty forged.training_mappings(fco_id: @outside_farmer.fco_id)
    end
    jj = FarmerTargetApi.new(current_app_user: { "record_type" => "Vrp", "id" => @mine.id }, module_slug: "training-form")
    assert_equal [@target.id.to_s], jj.training_mappings.map { |mapping| mapping[:target_mapping_id] }
  end

  def create_vrp(name, office, cluster)
    Vrp.create!(name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B", branch: "Br",
      ifsc_code: "TEST0123456", address: "A", mobile_no: "9876543210",
      email: "#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 55, password: "secret", fcoc: office, cluster_incharge: cluster)
  end

  def create_target(vrp, farmer, month, activity)
    TargetMapping.create!(vrp: vrp, fco_id: farmer.fco_id, fco_name: farmer.fco,
      ics_id: farmer.ics_id, ics_name: farmer.ics_name, village_id: farmer.village_id,
      village_name: farmer.village_name, month_name: month, main_activity_name: "Farmers' Training",
      activity_name: activity, target_quantity: 1, afl_ids: [farmer.id], week_wise_opg_target: 2, opg_training_target: 2)
  end

  def xlsx_text
    result = nil
    Zip::File.open_buffer(response.body) do |zip|
      result = zip.glob("xl/worksheets/*.xml").map { |entry| entry.get_input_stream.read }.join(" ")
    end
    result
  end

  def login(user)
    post login_path, params: { login: user.user_name, password: "secret" }
  end

  def calculator(user)
    controller = DashboardReportsController.new
    controller.define_singleton_method(:current_app_user) do
      { "id" => user.id, "record_type" => "User", "user_type" => user.user_type, "role" => user.role,
        "name" => user.full_name, "office_name" => user.office_name }
    end
    controller.params = ActionController::Parameters.new(month: "")
    controller
  end

  test "admin includes every AFL office and all-month main and sub indicators" do
    login(@admin)
    get dashboard_path, params: { month: "" }
    assert_response :success
    assert_select "#dash_fcoc option", text: /New Office/
    assert_select "#dash_sub_activity option", text: "Soil Preparation"
    assert_select "#dash_ics option", text: "ICS A"
    assert_select "#dash_ics option", text: "ICS B"
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Mapped Sub-Activities\s+2/
  end

  test "office scope covers every JJ in posting and rejects another office even with forged filter" do
    c = calculator(@staff)
    assert_equal [@mine.id, @same_office.id].sort, c.send(:dashboard_visible_vrp_ids).sort
    assert_equal [@farmer.id], c.send(:dashboard_visible_farmer_scope).pluck(:id)
    login(@staff)
    get demonstration_method_list_path, params: { month: "", fcoc: "New Office" }
    assert_response :success
    refute_includes response.body, "Outside JJ"
  end

  test "CC scope excludes JJs of another CC in the same office" do
    c = calculator(@cc)
    assert_equal [@mine.id], c.send(:dashboard_visible_vrp_ids)
    assert_equal [@target.id], c.send(:dashboard_visible_target_scope).pluck(:id)
    assert_equal [@farmer.id], c.send(:dashboard_visible_farmer_scope).pluck(:id)
  end

  test "other indicator HTML and Excel restore ICS and legacy sub indicator for selected month" do
    login(@staff)
    get other_indicator_list_path, params: { month: "September" }
    assert_response :success
    assert_includes response.body, "Legacy Sub"
    assert_includes response.body, "ICS A"
    get other_indicator_list_path, params: { month: "October" }
    assert_response :success
    refute_includes response.body, "Legacy Sub"
    get other_indicator_list_path(format: :xlsx), params: { month: "September" }
    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type
    assert_includes xlsx_text, "Legacy Sub"
    assert_includes xlsx_text, "ICS A"
  end

  test "demonstration list and export preserve all months and dynamic office scope" do
    login(@admin)
    get demonstration_method_list_path, params: { month: "" }
    assert_response :success
    assert_includes response.body, "Outside JJ"
    assert_select "table[data-paginated-table]"
    get demonstration_method_list_path(format: :xlsx), params: { month: "" }
    assert_response :success
    assert_equal XlsxExporter::MIME_TYPE, response.media_type
    assert_includes xlsx_text, "General Training/Meeting Target"
  end

  test "participation list searches across the full authorized population" do
    login(@admin)
    get farmer_training_participation_path, params: { training_month: "all", status: "red", search: "Outside Farmer" }
    assert_response :success
    assert_includes response.body, "Outside Farmer"
    refute_includes response.body, "Assigned Farmer"
    get farmer_training_participation_path(format: :xlsx), params: { training_month: "all", status: "red", search: "Outside Farmer" }
    assert_response :success
    assert_includes xlsx_text, "Outside Farmer"
    refute_includes xlsx_text, "Assigned Farmer"
  end
  test "summary lists and exports share office scope and selected month" do
    login(@staff)
    get dashboard_report_list_path("farmers"), params: { month: "" }
    assert_response :success
    assert_includes response.body, "Assigned Farmer"
    refute_includes response.body, "Outside Farmer"
    get dashboard_report_list_path("sub-indicators"), params: { month: "September" }
    assert_response :success
    assert_includes response.body, "Soil Preparation"
    refute_includes response.body, "Outside Indicator"
    get dashboard_report_list_path("sub-indicators", format: :xlsx), params: { month: "September" }
    assert_response :success
    assert_includes xlsx_text, "Soil Preparation"
    refute_includes xlsx_text, "Outside Indicator"
  end

  test "mapped farmer SQL list shows server pagination and exports all matching pages" do
    24.times do |index|
      farmer = Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "ics-a", ics_name: "ICS A",
        village_id: "v-a", village_name: "Village A", tracenet_no: "PAGE-#{index}", farmer_name: "PAGE FARMER #{index}")
      @target.afl_ids = (Array(@target.afl_ids) + [farmer.id.to_s]).uniq
    end
    @target.save!
    login(@admin)
    get farmer_training_participation_path, params: { status: "unique", training_month: "September" }
    assert_response :success
    assert_includes response.body, "Next"
    get farmer_training_participation_path, params: { status: "unique", training_month: "September", page: 2 }
    assert_response :success
    assert_includes response.body, "Previous"
    get farmer_training_participation_path(format: :xlsx), params: { status: "unique", training_month: "September", page: 2 }
    assert_response :success
    assert_includes xlsx_text, "PAGE FARMER 0"
    assert_includes xlsx_text, "PAGE FARMER 23"
  end

  test "CC status lists and exports only contain assigned JJs" do
    @target.update!(cc_target: 2)
    login(@cc)
    [cc_jj_work_status_list_path, cc_target_status_list_path].each do |path|
      get path, params: { month: "" }
      assert_response :success
      refute_includes response.body, "Outside JJ"
      refute_includes response.body, "Other CC JJ"
      get path, params: { month: "", format: :xlsx }
      assert_response :success
      assert_equal XlsxExporter::MIME_TYPE, response.media_type
      refute_includes xlsx_text, "Outside JJ"
    end
  end

  test "CC summary counts and farmer lists exclude unmapped farmers of the same office" do
    Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "ics-private", ics_name: "Unassigned ICS",
      village_id: "v-private", village_name: "Unassigned Village", tracenet_no: "UNASSIGNED", farmer_name: "Unassigned Farmer")
    c = calculator(@cc)
    assert_equal 1, c.send(:dashboard_total_afl_farmer_count)
    assert_equal 1, c.send(:dashboard_total_afl_ics_count)
    login(@cc)
    get dashboard_report_list_path("farmers"), params: { month: "" }
    assert_response :success
    refute_includes response.body, "Unassigned Farmer"
    get dashboard_path, params: { month: "" }
    assert_response :success
    refute_includes response.body, "Unassigned ICS"
  end

  test "demonstration all months adds monthly targets and attributes office-entered sessions to JJ" do
    create_target(@mine, @farmer, "October", "Soil Preparation")
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "September", "vrp_id" => @mine.id.to_s, "created_by_id" => @staff.id.to_s,
      "created_by_record_type" => "User", "training_method" => "General Training/Meeting",
      "selected_farmer_ids" => [@farmer.id.to_s], "main_activity" => "Farmers' Training", "main_activity_type" => "Training"
    })
    c = calculator(@staff)
    report = DashboardDemonstrationMethodReport.new(targets: c.send(:dashboard_target_mappings), month: "")
    assert_equal "4 / 1", report.rows.first["OPG Target / Done"]
    assert_equal "4 / 1", report.rows.first["General Training/Meeting"]
    assert_equal 4, report.summary.sum { |row| row["OPG Target"].to_i }
    assert_equal 1, report.summary.sum { |row| row["General Training/Meeting Done"].to_i }
  end

  test "admin cluster filter narrows every farmer summary and its list" do
    login(@admin)
    get dashboard_report_list_path("farmers"), params: { month: "", cluster_incharge: "Assigned CC" }
    assert_response :success
    assert_includes response.body, "Assigned Farmer"
    refute_includes response.body, "Outside Farmer"
    get dashboard_path, params: { month: "", cluster_incharge: "Assigned CC" }
    assert_response :success
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Farmer Count\s+1/
  end

  test "CC and JJ status links preserve their office and status in list and export" do
    login(@admin)
    get dashboard_path, params: { month: "" }
    assert_response :success
    assert_select ".cc-jj-status-fco-row a[href*='fcoc=995'][href*='work_status=Red']"
    get cc_jj_work_status_list_path, params: { month: "", fcoc: "995", work_status: "Red" }
    assert_response :success
    refute_includes response.body, "Outside JJ"
    get cc_jj_work_status_list_path(format: :xlsx), params: { month: "", fcoc: "995", work_status: "Red" }
    assert_response :success
    refute_includes xlsx_text, "Outside JJ"
  end

end
