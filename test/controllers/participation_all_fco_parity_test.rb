require "test_helper"

class ParticipationAllFcoParityTest < ActiveSupport::TestCase
  setup do
    DashboardFcoDirectory::Store.reset
    DashboardSqlCache::STORE.clear
    @farmers = 4.times.map do |index|
      Afl.create!(farmer_name: "All FCO farmer #{index}", fco_id: index.zero? ? nil : "all-fco-test",
        fco: "FCO-Test Office", village_name: "Test Village")
    end
    @vrp = Vrp.new(name: "Parity JJ", fcoc: "FCO-Test Office", aadhar_no: "123456789012",
      account_no: "123", address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current, email: "all-fco-test@example.test", experience_in_years: 0,
      father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210",
      office_detail_id: 0, to_office_detail_id: 0)
    @vrp.save!(validate: false)
    @target = TargetMapping.create!(vrp: @vrp, fco_id: "all-fco-test", fco_name: "Test Office",
      ics_id: "ics", village_id: "village", month_name: "September", main_activity_name: "Farmers' Training",
      activity_name: "Soil", target_quantity: 4, afl_ids: @farmers.map(&:id))
    @controller = calculator
    data = { "month" => "September", "main_activity_type" => "Training", "main_activity" => "Farmers' Training",
      "training_date" => "2026-09-03", "target_mapping_id" => @target.id.to_s }
    ModuleRecord.create!(module_slug: "training-form", data: data.merge(
      "selected_farmer_ids" => [@farmers[0].id.to_s, @farmers[1].id.to_s, @farmers[1].id.to_s, @farmers[2].id.to_s]))
    ModuleRecord.create!(module_slug: "training-form", data: data.merge("selected_farmer_ids" => [@farmers[2].id.to_s]))
  end

  test "all FCO keeps farmers with missing office IDs and empty months remain pending" do
    counts = @controller.send(:farmer_training_attendance_counts_by_fco, month_name: "September", fcoc_name: nil)
    assert_equal Afl.count, counts.sum { |row| row["total_farmer_count"].to_i }
    assert_equal 2, counts.sum { |row| row["yellow_count"].to_i }
    assert_equal 1, counts.sum { |row| row["green_count"].to_i }
    assert_equal Afl.count - 3, counts.sum { |row| row["red_farmer_count"].to_i }
    pending, = @controller.send(:farmer_training_no_training_count_and_popups, month_name: "December", fcoc_name: nil)
    assert_equal Afl.count, pending
  end

  test "selected office and all months use the same farmer identity and attendance as lists" do
    ["September", nil].each do |month|
      c = calculator
      mapped, = c.send(:farmer_training_mapped_farmer_count_and_popups, month_name: month, fcoc_name: "Test Office")
      assert_equal 4, mapped
      expected = { "red" => [@farmers[3].id.to_s], "yellow" => @farmers.first(2).map { |farmer| farmer.id.to_s },
        "green" => [@farmers[2].id.to_s] }
      expected.each do |status, ids|
        method = status == "red" ? :farmer_training_no_training_count_and_popups : "farmer_training_#{status}_farmer_count_and_popups".to_sym
        count, = c.send(method, month_name: month, fcoc_name: "Test Office")
        rows = c.send(:farmer_training_participation_rows_from_sql, status, month_name: month, fcoc_name: "Test Office")
        assert_equal ids.size, count
        assert_equal ids.sort, rows.map { |row| row[:farmer_id] }.sort
      end
    end
  end

  test "choosing another FCO cannot widen a staff viewer's office scope" do
    c = calculator
    c.define_singleton_method(:dashboard_global_view_user?) { false }
    c.define_singleton_method(:dashboard_visible_farmer_scope) { Afl.none }
    c.define_singleton_method(:dashboard_visible_target_scope) { TargetMapping.none }
    assert_equal 0, c.send(:farmer_training_no_training_count_and_popups, month_name: "September", fcoc_name: "Test Office").first
    assert_empty c.send(:farmer_training_participation_rows_from_sql, "yellow", month_name: "September", fcoc_name: "Test Office")
  end

  test "dashboard preloads the same JJ profile while omitting unused signatures" do
    @vrp.update_column(:agreement_signature_data, "x" * 100_000)
    c = calculator
    rows = c.send(:dashboard_target_mappings)
    target = rows.find { |row| row.id == @target.id }
    assert target.association(:vrp).loaded?
    assert_equal @vrp.attributes.except("agreement_signature_data"), target.vrp.attributes
    assert_not target.vrp.has_attribute?(:agreement_signature_data)
    assert_equal @vrp.id, c.send(:dashboard_vrps).find { |row| row.id == @vrp.id }.id
  end

  test "mapped farmer total does not double count the same farmer across office ID aliases" do
    copy = @target.dup
    copy.fco_id = "alternate-office-id"
    copy.afl_ids = [@farmers.first.id.to_s, "", " "]
    copy.save!
    DashboardFcoDirectory::Store.reset
    [nil, "Test Office"].each do |office|
      c = calculator
      count, = c.send(:farmer_training_mapped_farmer_count_and_popups, month_name: "September", fcoc_name: office)
      rows = c.send(:farmer_training_participation_rows_from_sql, "mapped", month_name: "September", fcoc_name: office)
      assert_equal 4, count
      assert_equal count, rows.map { |row| row[:farmer_id] }.uniq.size
    end
  end

  private

  def calculator
    controller = DashboardReportsController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new
    controller.define_singleton_method(:current_app_user) { { "user_type" => "admin", "record_type" => "User" } }
    controller
  end
end
