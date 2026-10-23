require "test_helper"

# target_mappings.afl_ids and the training form's selected_farmer_ids are text
# and jsonb columns that nothing forces to hold an array, and the reporting SQL
# expands both with jsonb_array_elements_text - which raises on anything that
# is not an array. Most call sites already guarded that with jsonb_typeof; the
# six query files under app/queries did not, so one bad value took a whole
# report down instead of that single row.
#
# These tests put a malformed value next to a good one and require the reports
# to keep returning the good rows, unchanged.
class FarmerQueryMalformedArrayTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(user_name: "mal_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    ModuleRecord.create!(module_slug: "access-control",
      data: { "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active" })
    @vrp = create_vrp("Malformed JJ", "FCO-C Bhawanipatna", "Assigned CC (Cluster Incharge)")
    @farmer = Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "ics-a", ics_name: "ICS A",
      village_id: "v-a", village_name: "Village A", tracenet_no: "FARMER-A", farmer_name: "Good Farmer")
    @target = create_target(@vrp, @farmer, "September", "Soil Preparation")
  end

  def create_vrp(name, office, cluster)
    Vrp.create!(name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B", branch: "Br",
      ifsc_code: "TEST0123456", address: "A", mobile_no: "9876543210",
      email: "#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      status: 55, password: "secret", fcoc: office, cluster_incharge: cluster)
  end

  def create_target(vrp, farmer, month, activity)
    TargetMapping.create!(vrp: vrp, fco_id: farmer.fco_id, fco_name: farmer.fco,
      ics_id: farmer.ics_id, ics_name: farmer.ics_name, village_id: farmer.village_id,
      village_name: farmer.village_name, month_name: month,
      main_activity_name: "Farmers' Training", activity_name: activity,
      target_quantity: 1, afl_ids: [farmer.id], week_wise_opg_target: 2, opg_training_target: 2)
  end

  def calculator(user)
    controller = DashboardReportsController.new
    controller.define_singleton_method(:current_app_user) do
      { "id" => user.id, "record_type" => "User", "user_type" => user.user_type,
        "role" => user.role, "name" => user.full_name, "office_name" => user.office_name }
    end
    controller.params = ActionController::Parameters.new(month: "")
    controller
  end

  # afl_ids carries a serializer, so writing through the model would re-encode
  # the value into a JSON string. Raw SQL is what reproduces the stored shapes
  # that actually appear - a bare object as well as a scalar.
  def break_afl_ids!(raw_json)
    bad = create_target(@vrp, @farmer, "September", "Broken Indicator")
    ActiveRecord::Base.connection.exec_update(
      "UPDATE target_mappings SET afl_ids = $1 WHERE id = $2", "break_afl_ids",
      [raw_json, bad.id]
    )
    bad
  end

  def training_form_with(selected)
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "September", "vrp_id" => @vrp.id.to_s,
      "training_method" => "General Training/Meeting",
      "selected_farmer_ids" => selected,
      "main_activity" => "Farmers' Training", "main_activity_type" => "Training"
    })
  end

  test "the malformed fixtures really are the shapes that make the expansion raise" do
    object_row = break_afl_ids!('{"not":"an array"}')
    scalar_row = break_afl_ids!('"plain string"')

    types = TargetMapping.where(id: [object_row.id, scalar_row.id])
      .pluck(Arel.sql("jsonb_typeof(afl_ids::jsonb)")).sort
    assert_equal ["object", "string"], types,
      "the fixtures must reproduce the shapes jsonb_array_elements_text rejects"
  end

  test "a malformed afl_ids contributes no farmers instead of breaking the report" do
    break_afl_ids!('{"not":"an array"}')
    break_afl_ids!('"plain string"')

    rows = nil
    assert_nothing_raised do
      rows = calculator(@admin).send(:farmer_training_participation_rows_from_sql,
        "mapped", month_name: nil, fcoc_name: nil)
    end

    # The guarded sites elsewhere treat a non-array as empty, so these rows must
    # add no farmer of their own while the good mapping still comes through.
    assert_equal [@farmer.id.to_s], rows.map { |row| row[:farmer_id] }.uniq,
      "a malformed afl_ids leaked farmers into the mapped report"
  end

  test "no-training counts survive a non-array selected_farmer_ids" do
    training_form_with([@farmer.id.to_s])
    expected, = calculator(@admin).send(:farmer_training_no_training_count_and_popups,
      month_name: nil, fcoc_name: nil)

    training_form_with("not-an-array")
    training_form_with({ "nested" => "object" })

    actual = nil
    assert_nothing_raised do
      actual, = calculator(@admin).send(:farmer_training_no_training_count_and_popups,
        month_name: nil, fcoc_name: nil)
    end

    assert_equal expected, actual
  end

  test "CC and JJ work status report survives both malformed shapes" do
    training_form_with([@farmer.id.to_s])
    break_afl_ids!('"plain string"')
    training_form_with("not-an-array")

    post login_path, params: { login: @admin.user_name, password: "secret" }

    assert_nothing_raised do
      get cc_jj_work_status_list_path, params: { month: "", fcoc: "995", work_status: "Red" }
    end
    assert_response :success

    assert_nothing_raised { get dashboard_path, params: { month: "" } }
    assert_response :success
  end
end
