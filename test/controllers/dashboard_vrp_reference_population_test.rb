require "test_helper"

class DashboardVrpReferencePopulationTest < ActionDispatch::IntegrationTest
  setup do
    DashboardFcoDirectory::Store.reset
    DashboardSqlCache::STORE.clear
    @farmers = 4.times.map do |i|
      Afl.create!(farmer_name: "Reference farmer #{i}", fco_id: i.zero? ? nil : " legacy-office ",
        fco: "FCO - Bhawanipatna", ics_id: "REF-ICS", ics_name: "Reference ICS",
        village_id: "REF-VILLAGE", village_name: "Reference Village", tracenet_no: "REFERENCE-#{i}")
    end
    @outside = Afl.create!(farmer_name: "Outside office", fco_id: "outside-office", fco: "FCO-Other",
      ics_id: "OTHER-ICS", village_id: "OTHER-VILLAGE", tracenet_no: "OUTSIDE")
    vrp = Vrp.new(name: "Reference JJ", fcoc: "FCO-Bhawanipatna", aadhar_no: "123456789012",
      account_no: "123", address: "Reference", branch: "Reference", date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current, email: "reference-population@example.test", experience_in_years: 0,
      father_husband_name: "Reference", gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210",
      office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    @target = TargetMapping.create!(vrp: vrp, fco_id: "target-office-id", fco_name: "Bhawanipatna",
      ics_id: "REF-ICS", village_id: "REF-VILLAGE", month_name: "October",
      main_activity_name: "Farmers' Training", activity_name: "Soil", target_quantity: 4,
      afl_ids: @farmers.map(&:id))
    data = { "month" => "October", "main_activity_type" => "Training", "main_activity" => "Farmers' Training",
      "training_date" => "2026-10-03", "target_mapping_id" => @target.id.to_s }
    ModuleRecord.create!(module_slug: "training-form", data: data.merge(
      "selected_farmer_ids" => [@farmers[0].id.to_s, @farmers[1].id.to_s, @farmers[1].id.to_s, @farmers[2].id.to_s]))
    ModuleRecord.create!(module_slug: "training-form", data: data.merge("selected_farmer_ids" => [@farmers[2].id.to_s]))
  end

  test "admin and office staff get VRP reference box counts with legacy IDs and office spellings" do
    [true, false].each do |admin|
      c = calculator(admin: admin)
      assert_equal @farmers.map(&:id).sort, c.send(:dashboard_total_afl_scope).pluck(:id).sort
      assert_equal 4, c.send(:dashboard_total_afl_farmer_count)
      assert_equal 2, c.send(:dashboard_total_afl_ics_count)
      # VRP groups village/ICS rows by FCO as well, preserving its grouping rules.
      assert_equal 2, c.send(:dashboard_total_afl_village_count)
      assert_equal 4, c.send(:farmer_training_mapped_farmer_count_and_popups, month_name: "October", fcoc_name: "Bhawanipatna").first
      { "red" => 1, "yellow" => 2, "green" => 1 }.each do |status, expected|
        method = { "red" => :farmer_training_no_training_count_and_popups,
          "yellow" => :farmer_training_yellow_farmer_count_and_popups,
          "green" => :farmer_training_green_farmer_count_and_popups }.fetch(status)
        assert_equal expected, c.send(method, month_name: "October", fcoc_name: "Bhawanipatna").first
        rows = c.send(:farmer_training_participation_rows_from_sql, status, month_name: "October", fcoc_name: "Bhawanipatna")
        assert_equal expected, rows.map { |row| row[:farmer_id] }.uniq.size
      end
    end
  end

  test "office staff cannot select another office to widen summary or participation" do
    c = calculator(admin: false)
    c.params = ActionController::Parameters.new(fcoc: "Other")
    c.instance_variable_set(:@dashboard_fcoc_filter_value, "Other")
    assert_empty c.send(:dashboard_total_afl_scope)
    assert_equal 0, c.send(:farmer_training_no_training_count_and_popups, month_name: "October", fcoc_name: "Other").first
  end

  test "actual admin and user logins render all four reference participation boxes" do
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active"
    })
    [true, false].each do |admin|
      user = User.create!(user_name: "reference_dashboard_#{admin}", password: "secret", first_name: "Reference",
        role: admin ? "Admin" : "Agronomist", user_type: admin ? "admin" : "User",
        office_name: "FCO-Bhawanipatna", status: "Active")
      post login_path, params: { login: user.user_name, password: "secret" }
      assert_response :redirect
      get dashboard_path, params: { month: "October", main_activity: "Farmers' Training", fcoc: "Bhawanipatna" }
      assert_response :success
      assert_select "#dashboard_summary_boxes .dashboard-summary-box", text: /Total Farmer Count\s+4/
      { "total" => 4, "red" => 1, "yellow" => 2, "green" => 1 }.each do |status, count|
        assert_select ".training-status-panel .training-participation-box.#{status} > strong", text: count.to_s
      end
      delete logout_path
    end
  end

  test "VRP reference counts span all months and an empty month leaves farmers pending" do
    c = calculator(admin: false)
    { "red" => 1, "yellow" => 2, "green" => 1 }.each do |status, expected|
      rows = c.send(:farmer_training_participation_rows_from_sql, status, month_name: nil, fcoc_name: "Bhawanipatna")
      assert_equal expected, rows.map { |row| row[:farmer_id] }.uniq.size
    end
    assert_equal 4, c.send(:farmer_training_no_training_count_and_popups, month_name: "December", fcoc_name: "Bhawanipatna").first
    assert_equal 0, c.send(:farmer_training_yellow_farmer_count_and_popups, month_name: "December", fcoc_name: "Bhawanipatna").first
    assert_equal 0, c.send(:farmer_training_green_farmer_count_and_popups, month_name: "December", fcoc_name: "Bhawanipatna").first
  end

  test "a missing office placeholder does not authorize unassigned farmer records" do
    Afl.create!(farmer_name: "Unassigned farmer", fco: "NULL")
    c = calculator(admin: false)
    c.define_singleton_method(:current_app_user) do
      { "record_type" => "User", "user_type" => "User", "role" => "Agronomist", "office_name" => "NULL" }
    end
    assert_empty c.send(:dashboard_user_visible_farmer_scope)
  end

  private

  def calculator(admin:)
    c = DashboardReportsController.new
    c.request = ActionDispatch::TestRequest.create
    c.params = ActionController::Parameters.new(fcoc: "Bhawanipatna")
    c.instance_variable_set(:@dashboard_fcoc_filter_value, "Bhawanipatna")
    user = { "record_type" => "User", "user_type" => admin ? "admin" : "User", "id" => "99999",
      "name" => "Reference staff", "role" => admin ? "Admin" : "Agronomist", "office_name" => "FCO-Bhawanipatna" }
    c.define_singleton_method(:current_app_user) { user }
    c
  end
end
