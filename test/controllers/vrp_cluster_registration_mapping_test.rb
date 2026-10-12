require "test_helper"

class VrpClusterRegistrationMappingTest < ActiveSupport::TestCase
  test "same name FCO cannot replace the mapped Petlawad cluster incharge" do
    User.create!(first_name: "Pritesh", last_name: "Jain (FCO-Jobat)", user_name: "a_pritesh_fco",
      email: "fco-jobat@example.test", password: "secret", role: "FCO-Jobat", status: "Active",
      office_name: "FCO-Jobat", sub_office_name: "TO-Jobat")
    cc = User.create!(first_name: "Pritesh", last_name: "Jain (TO-Petlawad-C1)", user_name: "z_pritesh_cc",
      email: "cc-petlawad@example.test", password: "secret", role: "Cluster Incharge", status: "Active",
      office_name: "FCO-Ranapur", sub_office_name: "TO-Petlawad")

    [VrpsController.new, Class.new(ApplicationController) { include VrpAccess }.new].each do |controller|
      mapping = controller.send(:cluster_mapping_from_hierarchy_label, "Pritesh Jain (Cluster Incharge)")
      result = controller.send(:enrich_cluster_mapping_from_user, mapping)
      assert_equal cc.full_name, result[:value]
      assert_equal "FCO-Ranapur", result[:office_category]
      assert_equal "TO-Petlawad", result[:office_name]
    end
  end

  test "cluster registration follows visible office name instead of stale category" do
    User.create!(first_name: "Petlawad", last_name: "Coordinator", user_name: "petlawad_cc",
      email: "petlawad-office@example.test", password: "secret", role: "Cluster Incharge", status: "Active",
      office_category: "Old office category", office_name: "FCO-Ranapur", sub_office_name: "TO-Petlawad")
    controller = VrpsController.new
    mapping = controller.send(:cluster_mapping_from_hierarchy_label, "Petlawad Coordinator (Cluster Incharge)")
    result = controller.send(:enrich_cluster_mapping_from_user, mapping)
    assert_equal "FCO-Ranapur", result[:office_category]
    assert_equal "TO-Petlawad", result[:office_name]
  end

  test "inactive CC does not override an active mapped identity" do
    User.create!(first_name: "Inactive", last_name: "Coordinator", user_name: "inactive_cc",
      email: "inactive-cc@example.test", password: "secret", role: "Cluster Incharge", status: "Inactive",
      office_name: "FCO-Ranapur", sub_office_name: "TO-Petlawad")
    controller = VrpsController.new
    mapping = controller.send(:cluster_mapping_from_hierarchy_label, "Inactive Coordinator (Cluster Incharge)")
    assert_equal mapping, controller.send(:enrich_cluster_mapping_from_user, mapping)
  end
end

class VrpClusterRegistrationFormTest < ActionDispatch::IntegrationTest
  test "mapped Petlawad CC reaches the registration form with their own FCO and TO" do
    admin = User.create!(first_name: "Registration", last_name: "Admin", user_name: "cc_form_admin",
      email: "cc-form-admin@example.test", password: "secret", user_type: "admin", status: "Active")
    User.create!(first_name: "Pritesh", last_name: "Jain (FCO-Jobat)", user_name: "a_cc_form_fco",
      email: "cc-form-fco@example.test", password: "secret", role: "FCO-Jobat", status: "Active",
      office_name: "FCO-Jobat", sub_office_name: "TO-Jobat")
    cc = User.create!(first_name: "Pritesh", last_name: "Jain (TO-Petlawad-C1)", user_name: "z_cc_form_cc",
      email: "cc-form-cc@example.test", password: "secret", role: "Cluster Incharge", status: "Active",
      office_name: "FCO-Ranapur", sub_office_name: "TO-Petlawad")
    ModuleRecord.create!(module_slug: "user-hierarchy-mapping", data: {
      "status" => "Active", "level_1_user" => "Pritesh Jain (FCO-Ranapur)",
      "level_2_mappings" => [{ "level_2_user" => "Pritesh Jain (Cluster Incharge)", "level_3_users" => [] }]
    })
    post login_path, params: { login: admin.user_name, password: "secret" }
    get new_vrp_path
    assert_response :success
    shell = Nokogiri::HTML(response.body).at_css("[data-vrp-office-form]")
    mappings = JSON.parse(shell["data-cluster-users"])
    mapping = mappings.find { |row| row["value"] == cc.full_name }
    assert_not_nil mapping
    assert_equal "FCO-Ranapur", mapping["office_category"]
    assert_equal "TO-Petlawad", mapping["office_name"]
    assert_select "[data-vrp-cluster-incharge] option", text: mapping["label"]
  end
end
