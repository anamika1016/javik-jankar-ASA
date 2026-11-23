require "test_helper"

class DashboardOfficeCascadeTest < ActionDispatch::IntegrationTest
  setup do
    @staff = User.create!(user_name: "jamtara_office_cascade", password: "secret", first_name: "Jamtara Staff",
      user_type: "User", role: "Agronomist", office_name: "FCO", sub_office_name: "Jamtara - FCO", status: "Active")
    ModuleRecord.create!(module_slug: "access-control", data: { "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active" })
    @items = [
      { "id" => 20, "name" => "Jamtara - FCO", "office_name" => { "name" => "FCO" } },
      { "id" => 64, "name" => "Jamtara - TO", "parent" => { "id" => 20 }, "territory_zones" => [zone(49, "Jamtara")] },
      { "id" => 68, "name" => "Ghaghra - TO (CFP)", "parent" => { "id" => 20 }, "territory_zones" => [zone(47, "Sarath"), zone(48, "Kundhit")] },
      { "id" => 102, "name" => "Gopikandar (OFO)", "parent" => { "id" => 20 }, "territory_zones" => [zone(67, "Gopikander")] },
      { "id" => 21, "name" => "Sausar - FCO", "office_name" => { "name" => "FCO" } },
      { "id" => 99, "name" => "Outside TO", "parent" => { "id" => 21 }, "territory_zones" => [zone(99, "Outside Block")] }
    ]
  end

  test "FCO login gets its Office List children and blocks without other offices" do
    with_directory do
      post login_path, params: { login: @staff.user_name, password: "secret" }
      get dashboard_path, params: { entry_mode: "block_wise", month: "" }
      assert_response :success
      assert_select "label[for=dash_office_id]", text: "Office Name"
      assert_select "#dash_office_id option[value='64']", text: "Jamtara - TO"
      assert_select "#dash_office_id option[value='68']", text: "Ghaghra - TO (CFP)"
      assert_select "#dash_office_id option[value='99']", count: 0
      assert_select "#dash_fcoc option", text: /Sausar/, count: 0
      assert_select "#dash_ics option", text: "Jamtara"
      assert_select "#dash_ics option", text: "Gopikander"
      get dashboard_path, params: { entry_mode: "block_wise", month: "", office_id: "68" }
      assert_response :success
      assert_select "#dash_ics option", text: "Sarath"
      assert_select "#dash_ics option", text: "Kundhit"
      assert_select "#dash_ics option", text: "Jamtara", count: 0
      assert_select "#dash_ics option", text: "Outside Block", count: 0
      assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "2"
      get dashboard_report_list_path("ics"), params: { entry_mode: "block_wise", month: "", office_id: "68" }
      assert_response :success
      assert_includes response.body, "Sarath"
      refute_includes response.body, "Gopikander"
    end
  end

  test "selected office filters block targets reports and keeps sibling block options available" do
    vrp = Vrp.create!(name: "Jamtara mapped JJ", fcoc: "Jamtara - FCO", is_active: true, is_deleted: false, status: 55,
      father_husband_name: "Father", gender: :male, date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "123456", bank_name: "Bank", branch: "Branch", ifsc_code: "TEST0123456",
      address: "Jamtara", mobile_no: "9876543210", email: "office_cascade_jj@example.test", experience_in_years: 0,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1], password: "secret")
    [[47, "Sarath"], [67, "Gopikander"]].each do |id, name|
      TargetMapping.create!(vrp: vrp, target_entry_mode: "block_wise", fco_id: "20", fco_name: "Jamtara",
        ics_id: id.to_s, ics_name: name, village_id: "v-#{id}", village_name: "#{name} Village",
        month_name: "November", main_activity_name: "Farmers' Training", activity_name: "Soil",
        target_quantity: 1, afl_ids: ["ASA-#{id}"])
    end
    with_directory do
      post login_path, params: { login: @staff.user_name, password: "secret" }
      get dashboard_path, params: { entry_mode: "block_wise", month: "", office_id: "68", ics: "Sarath" }
      assert_response :success
      assert_select "#dash_ics option", text: "Sarath"
      assert_select "#dash_ics option", text: "Kundhit"
      assert_select ".dashboard-view-switch-item.active b", text: "1 targets"
      get dashboard_report_list_path("villages"), params: { entry_mode: "block_wise", month: "", office_id: "68" }
      assert_response :success
      assert_includes response.body, "Sarath Village"
      refute_includes response.body, "Gopikander Village"
    end
  end

  test "a forged office ID cannot select another FCO's master blocks" do
    with_directory do
      post login_path, params: { login: @staff.user_name, password: "secret" }
      get dashboard_path, params: { entry_mode: "block_wise", month: "", office_id: "99" }
      assert_response :success
      assert_select "#dash_ics option", text: "Outside Block", count: 0
      assert_select "#dashboard_summary_boxes .dashboard-summary-box:first-child strong", text: "0"
    end
  end

  private

  def zone(id, name)
    { "block" => [{ "id" => id, "name" => { "en" => name } }] }
  end

  def with_directory
    original = OfficeTerritoryDirectory.method(:items)
    OfficeTerritoryDirectory.define_singleton_method(:items) { @test_items }
    OfficeTerritoryDirectory.instance_variable_set(:@test_items, @items)
    yield
  ensure
    OfficeTerritoryDirectory.define_singleton_method(:items, original)
    OfficeTerritoryDirectory.remove_instance_variable(:@test_items)
  end
end
