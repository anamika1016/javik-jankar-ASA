require "test_helper"

# The dashboard's ICS Wise / Block Wise / Both switcher. Target Mapping writes
# both kinds of target into target_mappings and Block Wise reuses the
# ics_id/ics_name columns for the block, so target_entry_mode is the only thing
# telling the two apart.
class DashboardEntryModeViewTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "entry_mode_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    ModuleRecord.create!(module_slug: "access-control",
      data: { "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active" })
    @vrp = create_vrp("Entry Mode JJ", "FCO-C Bhawanipatna")
    @farmer = Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "ics-a", ics_name: "ICS Alpha",
      village_id: "v-a", village_name: "Village A", tracenet_no: "FARMER-A", farmer_name: "ICS Farmer")

    @ics_target = create_target(mode: "ics_wise", ics_id: "ics-a", ics_name: "ICS Alpha",
      village_id: "v-a", village_name: "Village A", afl_ids: [@farmer.id.to_s])
    @block_target = create_target(mode: "block_wise", ics_id: "blk-7", ics_name: "Jetpur Pavi",
      village_id: %w[178 179].to_json, village_name: "Bhikhapura, Borkanda",
      afl_ids: %w[GUCH1393BA361OG GUCH0425BS976OG])
  end

  test "all three views are offered and Both is the default" do
    login(@admin)
    get dashboard_path
    assert_response :success
    assert_select ".dashboard-view-switch-item", 3
    assert_equal ["Both", "ICS Wise", "Block Wise"], css_select(".dashboard-view-switch-item span").map(&:text)
    ["ICS Wise", "Block Wise", "Both"].each do |label|
      assert_select ".dashboard-view-switch-item span", text: label
    end
    assert_select ".dashboard-view-switch-item.active span", text: "Both"
  end

  test "population cards and lists count identities once across imported name and FPO variants" do
    Afl.create!(fco_id: @farmer.fco_id, fco: "FCO-C Bhawanipatna", fpo_id: "import-variant",
      fpo_name: "Different imported FPO", ics_id: " ics-a ", ics_name: "ICS ALPHA",
      village_id: " v-a ", village_name: "VILLAGE A", tracenet_no: " FARMER-A ", farmer_name: "Duplicate import")
    c = calculator(@admin, entry_mode: "ics_wise", month: "")
    assert_equal 1, c.send(:dashboard_total_afl_ics_count)
    assert_equal 1, c.send(:dashboard_total_afl_village_count)
    assert_equal 1, c.send(:dashboard_total_afl_farmer_count)
    %w[ics villages farmers].each do |type|
      assert_equal 1, c.send(:dashboard_report_data, type).last.size, type
    end
    login(@admin)
    get dashboard_path, params: { entry_mode: "both", month: "" }
    assert_response :success
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "2"
    assert_select ".dashboard-fco-table tbody th", text: "Bhawanipatna", count: 1
  end

  test "office aliases from the same saved office appear only once" do
    Afl.create!(fco_id: @farmer.fco_id, fco: "Bhawanipatna - FCO", tracenet_no: "ALIAS-1", farmer_name: "Alias farmer")
    c = calculator(@admin, month: "")
    names = c.send(:dashboard_fco_names)
    assert_equal ["Bhawanipatna"], names.grep(/bhawanipatna/i)
  end

  test "JJ requirement is derived from selected targets and expands multi village assignments" do
    c = calculator(@admin, month: "")
    c.request = ActionDispatch::TestRequest.create
    target = TargetMapping.new(fco_id: "1004", fco_name: "Sausar", village_id: '["v1","v2"]', village_name: "One, Two")
    c.define_singleton_method(:dashboard_fco_active_vrp_count) { |*| 1 }
    items = c.send(:dashboard_jj_requirement_items, "Sausar", [], [target, target])
    assert_equal [2, 1, 1], items.map { |item| item[:value] }
  end

  test "master blocks with no target appear in count list and picker" do
    offices = [{ "id" => 15, "name" => "Bhawanipatna - FCO", "office_name" => { "name" => "FCO" },
      "territory_zones" => [{ "block" => [
        { "id" => 42, "name" => { "en" => "Bhawanipatna" } },
        { "id" => 43, "name" => { "en" => "Kesinga" } },
        { "id" => 43, "name" => { "en" => "Kesinga duplicate" } }
      ] }] }]
    c = calculator(@admin, entry_mode: "block_wise", fcoc: "Bhawanipatna", month: "")
    c.define_singleton_method(:dashboard_office_list_items) { offices }
    assert_equal 2, c.send(:dashboard_block_entry_location_counts)[:ics_count]
    rows = c.send(:dashboard_report_data, "ics").last
    assert_equal %w[42 43], rows.map { |row| row["Block ID"] }
    login(@admin)
    original_items = OfficeTerritoryDirectory.method(:cached_items)
    OfficeTerritoryDirectory.define_singleton_method(:cached_items) { offices }
    begin
      get dashboard_path, params: { entry_mode: "block_wise", fcoc: "Bhawanipatna", month: "" }
      assert_response :success
      assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "2"
      assert_select "#dash_ics option", text: "Kesinga"
    ensure
      OfficeTerritoryDirectory.define_singleton_method(:cached_items, original_items)
    end
  end

  test "master block filter cannot widen an office login to another FCO" do
    staff = User.create!(user_name: "master_block_staff", password: "secret", first_name: "Office", user_type: "User",
      role: "Agronomist", office_name: "FCO-Bhawanipatna", status: "Active")
    c = calculator(staff, entry_mode: "block_wise", fcoc: "Sausar")
    offices = [{ "id" => 20, "name" => "Sausar-FCO", "office_name" => { "name" => "FCO" },
      "territory_zones" => [{ "block" => [{ "id" => 1, "name" => { "en" => "Outside block" } }] }] }]
    c.define_singleton_method(:dashboard_office_list_items) { offices }
    assert_empty c.send(:dashboard_block_master_rows)
  end

  test "legacy FCO spelling variants form one popup row" do
    assert_equal AgreementVrpScope.office_key("FCO-Bhabhra"), AgreementVrpScope.office_key("Bhabra")
    assert_equal AgreementVrpScope.office_key("FCO-Jamatara"), AgreementVrpScope.office_key("Jamtara-FCO")
    Afl.create!(fco_id: "bhabra-office", fco: "Bhabra", farmer_name: "Bhabra farmer")
    Afl.create!(fco_id: "jamtara-office", fco: "Jamatara", farmer_name: "Jamtara farmer")
    c = calculator(@admin, month: "")
    offices = %w[Bhabhra Jamtara].map { |name| { "name" => "#{name}-FCO", "office_name" => { "name" => "FCO" } } }
    c.define_singleton_method(:dashboard_office_list_items) { offices }
    assert_equal 1, c.send(:dashboard_fco_names).count { |name| name == "Bhabra" }
    assert_equal 1, c.send(:dashboard_fco_names).count { |name| name == "Jamtara" }
  end

  test "TO options follow the selected FCO and filter its targets" do
    @vrp.update!(to_name: "TO-Bhawanipatna")
    [["FCO-C Bhawanipatna", "TO-Bhawanipatna"], ["FCO-C Sausar", "TO-Sausar"]].each do |office, name|
      ModuleRecord.create!(module_slug: "office-mapping-add", data: {
        "office_name" => office, "sub_office_name" => name, "status" => "Active"
      })
    end
    login(@admin)
    get dashboard_path, params: { fcoc: "Bhawanipatna", to_name: "TO-Bhawanipatna", month: "" }
    assert_response :success
    assert_select "#dash_to_name option", text: "TO-Bhawanipatna"
    assert_select "#dash_to_name option", text: "TO-Sausar", count: 0
    assert_select "#dash_to_name option[selected]", text: "TO-Bhawanipatna"
    assert_equal 2, visible_target_count(to_name: "TO-Bhawanipatna")
    assert_equal 0, visible_target_count(to_name: "TO-Sausar")
  end

  test "an unknown entry_mode falls back to Both rather than hiding every target" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "nonsense" }
    assert_response :success
    assert_select ".dashboard-view-switch-item.active span", text: "Both"
  end

  test "each view counts only its own target mappings" do
    assert_equal 1, visible_target_count(entry_mode: "ics_wise")
    assert_equal 1, visible_target_count(entry_mode: "block_wise")
    assert_equal 2, visible_target_count(entry_mode: "both")
    assert_equal 2, visible_target_count({}), "no entry_mode must behave like Both"
  end

  test "the switcher badges report each view's target count" do
    login(@admin)
    get dashboard_path, params: { month: "" }
    assert_response :success
    assert_select ".dashboard-view-switch-item.active span", text: "Both"
    assert_select ".dashboard-view-switch-item", text: /Both\s*2/
    assert_select ".dashboard-view-switch-item", text: /ICS Wise\s*1/
    assert_select ".dashboard-view-switch-item", text: /Block Wise\s*1/
  end

  test "the location filter is relabelled for the selected view" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "block_wise" }
    assert_response :success
    assert_select "label[for=dash_ics]", text: "Block"

    get dashboard_path, params: { entry_mode: "ics_wise" }
    assert_select "label[for=dash_ics]", text: "ICS Name"

    get dashboard_path, params: { entry_mode: "both" }
    assert_select "label[for=dash_ics]", text: "ICS / Block"
  end

  test "applying filters and clearing them keep the selected view" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "block_wise" }
    assert_response :success
    assert_select "#dashboard-filter-form input[type=hidden][name=entry_mode][value=block_wise]"
    assert_select "#dash_clear_filters[href*='entry_mode=block_wise']"
  end

  test "the Block Wise view counts blocks, villages and farmers off the target rows" do
    # The farmer master only covers ICS Wise work, so these have to come from
    # the target row itself: one block, its two villages, its two ASA farmers.
    counts = calculator(@admin, entry_mode: "block_wise").send(:dashboard_block_entry_location_counts)
    assert_equal({ ics_count: 1, village_count: 2, farmer_count: 2 }, counts)
  end

  test "the Block Wise summary boxes replace the farmer-master totals" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "block_wise", month: "" }
    assert_response :success
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Block Count\s+1/
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Villages Count\s+2/
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Farmer Count\s+2/
  end

  test "the Both view adds the block side on top of the farmer master" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "both", month: "" }
    assert_response :success
    # One ICS from the farmer master plus one block from the target row.
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total ICS \+ Block Count\s+2/
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Villages Count\s+3/
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Farmer Count\s+3/
  end

  test "the ICS Wise view leaves the farmer-master totals untouched" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "ics_wise", month: "" }
    assert_response :success
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total ICS Count\s+1/
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Villages Count\s+1/
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Farmer Count\s+1/
  end

  test "the summary box View List matches the box it sits under" do
    login(@admin)
    get dashboard_report_list_path("ics", entry_mode: "block_wise", month: "")
    assert_response :success
    assert_select "td", text: "Jetpur Pavi"
    assert_select "td", text: "ICS Alpha", count: 0

    get dashboard_report_list_path("ics", entry_mode: "ics_wise", month: "")
    assert_response :success
    assert_select "td", text: "ICS Alpha"
    assert_select "td", text: "Jetpur Pavi", count: 0
  end

  # The ICS / Village / Farmer boxes count a population, and on the ICS Wise
  # side that population comes from the farmer master, which carries no
  # activity. Filtering the Block Wise half by activity would leave the two
  # halves of one total disagreeing with each other and with the View List.
  test "the Block Wise boxes ignore the activity filter, as the ICS side does" do
    create_target(mode: "block_wise", ics_id: "blk-9", ics_name: "Other Block",
      village_id: "901", village_name: "Village Nine", afl_ids: ["GUCHOTHER01OG"])

    login(@admin)
    get dashboard_path, params: { entry_mode: "block_wise", month: "", main_activity: "Farmers' Training" }
    assert_response :success
    # Both blocks are counted even though only one carries Farmers' Training.
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Block Count\s+2/

    get dashboard_report_list_path("ics", entry_mode: "block_wise", month: "", main_activity: "Farmers' Training")
    assert_response :success
    assert_select "tbody tr", 2, "the View List must show exactly what the box counted"
  end

  # An Other Target entry is an achievement against one target mapping, so it
  # has to follow that mapping's view -- and the two views still have to add up
  # to Both.
  test "Main Major Work Indicator - Other follows the target mapping's view" do
    create_other_target(@ics_target, target: "10", achievement: "4")
    create_other_target(@block_target, target: "25", achievement: "20")

    login(@admin)
    get dashboard_path, params: { entry_mode: "ics_wise", month: "", main_activity: "Other Work" }
    assert_response :success
    assert_select "#other_major_work_indicator_boxes .dashboard-summary-box", text: /Targeted Farmer\s+10/

    get dashboard_path, params: { entry_mode: "block_wise", month: "", main_activity: "Other Work" }
    assert_response :success
    assert_select "#other_major_work_indicator_boxes .dashboard-summary-box", text: /Targeted Farmer\s+25/

    get dashboard_path, params: { entry_mode: "both", month: "", main_activity: "Other Work" }
    assert_response :success
    assert_select "#other_major_work_indicator_boxes .dashboard-summary-box", text: /Targeted Farmer\s+35/
  end

  test "an Other Target entry with no mapping id counts as ICS Wise so the views still add up" do
    ModuleRecord.create!(module_slug: "other-target", data: {
      "jeevika_jankar_id" => @vrp.id.to_s, "jeevika_jankar_name" => @vrp.name,
      "fcoc_name" => @vrp.fcoc, "month" => "September", "ics" => "ICS Alpha",
      "training_topic" => "Legacy Main", "training_subject" => "Legacy Sub",
      "target" => "7", "achievement" => "3", "status" => "Active"
    })

    login(@admin)
    get dashboard_path, params: { entry_mode: "ics_wise", month: "", main_activity: "Other Work" }
    assert_select "#other_major_work_indicator_boxes .dashboard-summary-box", text: /Targeted Farmer\s+7/

    get dashboard_path, params: { entry_mode: "block_wise", month: "", main_activity: "Other Work" }
    assert_select "#other_major_work_indicator_boxes .dashboard-summary-box", text: /Targeted Farmer\s+0/

    get dashboard_path, params: { entry_mode: "both", month: "", main_activity: "Other Work" }
    assert_select "#other_major_work_indicator_boxes .dashboard-summary-box", text: /Targeted Farmer\s+7/
  end

  test "the switcher replaces the live clock in the topbar" do
    login(@admin)
    get dashboard_path
    assert_response :success
    assert_select ".dashboard-topbar .dashboard-view-switch"
    assert_select ".dashboard-topbar .dashboard-header-clock", 0
    assert_select "[data-dashboard-clock-time]", 0
  end

  test "the Both view shows each box's ICS and Block split under the total" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "both", month: "" }
    assert_response :success
    # The farmer master and the office directory are separate universes, so the
    # two sides add up: one ICS + one block; one master village + the block
    # target's two; one master farmer + the block target's two.
    assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child" do
      assert_select "strong", text: "2"
      assert_select ".dashboard-summary-split", text: /ICS 1 \+ Block 1/
    end
    boxes = css_select("#dashboard_summary_boxes .dashboard-summary-box").map { |box| box.text.gsub(/\s+/, " ").strip }
    assert(boxes.any? { |box| box.start_with?("Total Villages Count 3 ICS 1 + Block 2") }, boxes.inspect)
    assert(boxes.any? { |box| box.start_with?("Total Farmer Count 3 ICS 1 + Block 2") }, boxes.inspect)
  end

  test "the single-side views show no split" do
    login(@admin)
    ["ics_wise", "block_wise"].each do |mode|
      get dashboard_path, params: { entry_mode: mode, month: "" }
      assert_response :success
      assert_select ".dashboard-summary-split", 0, "#{mode} is one side already"
    end
  end

  # Opening on a month with nothing mapped showed a dashboard of zeros, which
  # reads as broken rather than as "nothing recorded for this month yet".
  test "a current month with no targets opens on All Months instead of zeros" do
    login(@admin)
    get dashboard_path
    assert_response :success
    assert_select "#dash_month option[selected]", 0, "no single month should be pinned"
    assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Farmer Count\s*3/
  end

  test "a current month that does have targets still opens on it" do
    create_target(mode: "ics_wise", ics_id: "ics-a", ics_name: "ICS Alpha",
      village_id: "v-a", village_name: "Village A", afl_ids: [@farmer.id.to_s],
      month: Date.current.strftime("%B"))

    login(@admin)
    get dashboard_path
    assert_response :success
    assert_select "#dash_month option[selected]", text: Date.current.strftime("%B")
  end

  # Block Wise farmers come from the ASA directory and are not in the local
  # farmer master, so the master's training history must not leak in as if it
  # described them.
  test "Block Wise does not report the ICS farmer population's training history" do
    login(@admin)
    get dashboard_path, params: { entry_mode: "block_wise", month: "" }
    assert_response :success
    assert_select ".training-status-panel .dashboard-summary-box", text: /Mapped Farmer\s*2/
    assert_select ".training-status-panel .dashboard-panel-note", text: /ASA directory/

    get dashboard_path, params: { entry_mode: "ics_wise", month: "" }
    assert_response :success
    assert_select ".training-status-panel .dashboard-panel-note", 0
  end

  test "each view exports the rows its View List shows" do
    login(@admin)
    get dashboard_report_list_path("ics", entry_mode: "block_wise", month: "", format: :xlsx)
    assert_response :success
    sheet = xlsx_text
    assert_includes sheet, "Jetpur Pavi"
    assert_not_includes sheet, "ICS Alpha"
  end

  test "editing a Block Wise target reopens on the Block Wise picker" do
    login(@admin)
    get target_mappings_path, params: { edit_id: @block_target.id }
    assert_response :success
    assert_select "[data-target-entry-mode] option[value=block_wise][selected]"

    get target_mappings_path, params: { edit_id: @ics_target.id }
    assert_response :success
    assert_select "[data-target-entry-mode] option[value=ics_wise][selected]"
  end

  private

  def visible_target_count(filter_params)
    calculator(@admin, **filter_params.symbolize_keys).send(:dashboard_visible_target_scope).count
  end

  def create_vrp(name, office)
    Vrp.create!(name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B", branch: "Br",
      ifsc_code: "TEST0123456", address: "A", mobile_no: "9876543210",
      email: "#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1],
      village_ids: [1], is_active: true, is_deleted: false, status: 55, password: "secret",
      fcoc: office, cluster_incharge: "Assigned CC (Cluster Incharge)")
  end

  def create_target(mode:, ics_id:, ics_name:, village_id:, village_name:, afl_ids:, month: "September")
    TargetMapping.create!(vrp: @vrp, fco_id: "995", fco_name: "Bhawanipatna",
      ics_id: ics_id, ics_name: ics_name, village_id: village_id, village_name: village_name,
      month_name: month, main_activity_name: "Farmers' Training",
      activity_name: "Soil Preparation", target_quantity: afl_ids.size, afl_ids: afl_ids,
      week_wise_opg_target: 2, opg_training_target: 2, target_entry_mode: mode)
  end

  def create_other_target(mapping, target:, achievement:)
    ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => mapping.id.to_s,
      "jeevika_jankar_id" => @vrp.id.to_s, "jeevika_jankar_name" => @vrp.name,
      "fcoc_name" => @vrp.fcoc, "month" => "September",
      "ics" => mapping.ics_name, "training_topic" => "Other Work",
      "training_subject" => "Other Sub", "target" => target,
      "achievement" => achievement, "status" => "Active"
    })
  end

  def login(user)
    post login_path, params: { login: user.user_name, password: "secret" }
  end

  def xlsx_text
    result = nil
    Zip::File.open_buffer(response.body) do |zip|
      result = zip.glob("xl/worksheets/*.xml").map { |entry| entry.get_input_stream.read }.join(" ")
    end
    result
  end

  def calculator(user, **filter_params)
    controller = DashboardReportsController.new
    controller.define_singleton_method(:current_app_user) do
      { "id" => user.id, "record_type" => "User", "user_type" => user.user_type, "role" => user.role,
        "name" => user.full_name, "office_name" => user.office_name }
    end
    controller.params = ActionController::Parameters.new(month: "", **filter_params)
    controller
  end
end
