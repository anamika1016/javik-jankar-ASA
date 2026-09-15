require "test_helper"

class VrpAgreementsControllerTest < ActionDispatch::IntegrationTest
  test "accepted agreement list shows signed vrps" do
    vrp = create_vrp(
      user_name: "signed_vrp",
      password: "secret",
      agreement_accepted_at: Time.current,
      agreement_signature_data: "data:image/png;base64,signature"
    )
    create_vrp(
      user_name: "unsigned_vrp",
      password: "secret",
      agreement_accepted_at: Time.current
    )

    post login_path, params: { login: "signed_vrp", password: "secret" }
    follow_redirect!

    get vrp_agreements_path

    assert_response :success
    assert_includes response.body, "Accepted Agreement by Jeevika Jankar"
    assert_includes response.body, vrp.name
    refute_includes response.body, "unsigned_vrp"
  end

  test "accepted agreement detail page shows signature" do
    vrp = create_vrp(
      user_name: "detail_vrp",
      password: "secret",
      agreement_accepted_at: Time.current,
      agreement_signature_data: "data:image/png;base64,signature"
    )

    post login_path, params: { login: "detail_vrp", password: "secret" }
    follow_redirect!

    get vrp_agreement_record_path(vrp)

    assert_response :success
    assert_includes response.body, "Signed Agreement"
    assert_includes response.body, "data:image/png;base64,signature"
  end

  test "accepted agreement delete resets signature requirement" do
    vrp = create_vrp(
      user_name: "reset_agreement_vrp",
      password: "secret",
      agreement_accepted_at: Time.current,
      agreement_signature_data: "data:image/png;base64,signature"
    )

    post login_path, params: { login: "reset_agreement_vrp", password: "secret" }
    follow_redirect!

    delete reset_vrp_agreement_path(vrp)

    assert_redirected_to vrp_agreements_path
    assert_nil vrp.reload.agreement_accepted_at
    assert_nil vrp.agreement_signature_data

    delete logout_path
    post login_path, params: { login: "reset_agreement_vrp", password: "secret" }

    assert_redirected_to vrp_agreement_path
  end

  test "FCOC and CC see assigned signed agreements created by other users" do
    assigned = create_vrp(name: "Assigned JJ", user_name: "assigned_jj", fcoc: "FCO Betul", cluster_incharge: "Cluster Reviewer", created_by_id: 999999,
      agreement_accepted_at: Time.current, agreement_signature_data: "data:image/png;base64,signature")
    unrelated = create_vrp(name: "Unrelated JJ", user_name: "unrelated_jj", fcoc: "FCO Other", cluster_incharge: "Other Reviewer", created_by_id: 999999,
      agreement_accepted_at: Time.current, agreement_signature_data: "data:image/png;base64,signature")
    [
      { "id" => 888888, "record_type" => "User", "username" => "fco_reviewer", "name" => "FCO Reviewer", "office_name" => "FCO Betul" },
      { "id" => 888889, "record_type" => "User", "username" => "cc_reviewer", "name" => "Cluster Reviewer", "role" => "Cluster Incharge" }
    ].each do |user|
      controller = VrpAgreementsController.new
      controller.request = ActionDispatch::TestRequest.create
      controller.instance_variable_set(:@current_app_user, user)
      rows = controller.send(:accepted_agreement_rows)
      assert_includes rows.map { |row| row[:id] }, assigned.id
      refute_includes rows.map { |row| row[:id] }, unrelated.id
    end
  end

  test "FCOC sees every signed JJ in the office and CC only its assigned JJs after login" do
    user = User.create!(user_name: "agreement_fco", password: "secret", first_name: "Binit", last_name: "Kumar",
      role: "FCOC", office_name: "Betul-FCO", user_type: "User", status: "Active")
    first = create_vrp(name: "First Mapped JJ", user_name: "first_mapping", fcoc: "FCO-C Betul", cluster_incharge: "Vikas Meena (CC)",
      agreement_accepted_at: Time.current, agreement_signature_data: "data:image/png;base64,signature")
    second = create_vrp(name: "Second Mapped JJ", user_name: "second_mapping", fcoc: "FCO-C Betul", cluster_incharge: "Different CC",
      agreement_accepted_at: Time.current, agreement_signature_data: nil)
    outside = create_vrp(name: "Outside Mapped JJ", user_name: "outside_mapping", fcoc: "FCO-C Other", cluster_incharge: "Different CC",
      agreement_accepted_at: Time.current, agreement_signature_data: "data:image/png;base64,signature")
    unsigned = create_vrp(name: "Unsigned Mapped JJ", user_name: "unsigned_mapping", fcoc: "FCO-C Betul", cluster_incharge: "Vikas Meena")
    post login_path, params: { login: user.user_name, password: "secret" }
    get vrp_agreements_path
    assert_response :success
    assert_includes response.body, first.name
    assert_includes response.body, second.name
    refute_includes response.body, outside.name
    refute_includes response.body, unsigned.name

    # A role/mapping update takes effect without requiring logout.
    user.update!(first_name: "Vikas", last_name: "Meena", role: "CC")
    get vrp_agreements_path
    assert_response :success
    assert_includes response.body, first.name
    refute_includes response.body, second.name
    refute_includes response.body, outside.name
    get vrp_agreement_record_path(first)
    assert_response :success
    get vrp_agreement_record_path(second)
    assert_redirected_to vrp_agreements_path
  end

  test "admin target mapping renders saved targets despite old failed office cache" do
    user = User.create!(user_name: "mapping_regression_admin", password: "secret", first_name: "Admin", user_type: "admin", status: "Active")
    vrp = create_vrp(user_name: "mapping_regression_jj")
    TargetMapping.create!(vrp: vrp, fco_id: "F1", ics_id: "I1", village_id: "V1", month_name: "July", main_activity_name: "Training", activity_name: "OPG Training", target_quantity: 4)
    Rails.cache.write("office-list-api-items-v1", ["https://example.test/offices"])
    Rails.cache.write("office-list-api-items-v2", [])
    post login_path, params: { login: user.user_name, password: "secret" }
    get target_mappings_path
    assert_response :success
    assert_includes response.body, "OPG Training"

    # Simulate a running server whose schema does not yet expose the CC column.
    previous_ignored_columns = TargetMapping.ignored_columns
    TargetMapping.ignored_columns = previous_ignored_columns + ["cc_target"]
    get target_mappings_path
    assert_response :success
    get target_mappings_path, params: { edit_id: TargetMapping.last.id }
    assert_response :success
  ensure
    TargetMapping.ignored_columns = previous_ignored_columns if previous_ignored_columns
    Rails.cache.delete("office-list-api-items-v1")
    Rails.cache.delete("office-list-api-items-v2")
  end

  test "admin archive and acceptance report include all 105 accepted records" do
    admin = User.create!(user_name: "full_archive_admin", password: "secret", first_name: "Archive Admin", user_type: "admin", status: "Active")
    105.times do |index|
      create_vrp(name: "Archive JJ #{index}", user_name: "archive_jj_#{index}", agreement_accepted_at: Time.current,
        agreement_signature_data: index.even? ? "data:image/png;base64,signature" : nil)
    end
    post login_path, params: { login: admin.user_name, password: "secret" }
    get vrp_agreements_path
    assert_response :success
    assert_select ".agreement-archive-table tbody tr", count: 105
    assert_select ".agreement-archive-table[data-page-size='105']"
    assert_includes response.body, "Signature missing"
    report = ModulesController.new.send(:vrp_declaration_acceptance_report)
    assert_equal 105, report[:rows].size
  end

  private

  def create_vrp(attributes = {})
    defaults = {
      name: "Test VRP",
      father_husband_name: "Test Father",
      gender: :male,
      date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current,
      aadhar_no: "123456789012",
      account_no: "1234567890",
      bank_name: "Test Bank",
      branch: "Test Branch",
      ifsc_code: "TEST0123456",
      address: "Test Address",
      mobile_no: "9876543210",
      email: "vrp#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1,
      office_detail_id: 0,
      to_office_detail_id: 0,
      vrp_type_ids: [1],
      gram_panchayat_ids: [1],
      village_ids: [1],
      is_active: true,
      is_deleted: false
    }

    Vrp.create!(defaults.merge(attributes))
  end
end
