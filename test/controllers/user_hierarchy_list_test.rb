require "test_helper"

# "Cluster Incharge Under Jeevika Jankar User" reads the records saved by
# "User Hierarchy Mapping", so both screens must surface a saved mapping.
class UserHierarchyListTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(user_name: "hierarchy_admin", password: "secret", first_name: "Admin",
                 user_type: "admin", status: "Active")
    post login_path, params: { login: "hierarchy_admin", password: "secret" }
  end

  def create_mapping(head:, subordinate:)
    ModuleRecord.create!(module_slug: "user-hierarchy-mapping", data: {
      "stakeholder_category" => "PAPL",
      "level_1_user" => head,
      "status" => "Active",
      "level_2_mappings" => [{ "level_2_user" => subordinate, "level_3_users" => [] }],
      "level_2_users" => [subordinate],
      "level_2_user" => subordinate,
      "level_3_users" => [], "level_3_user" => ""
    })
  end

  test "the mapping screen lists every saved record, whatever the subordinate role" do
    create_mapping(head: "Hemant shakkrapude (FCO-C Sausar)",
                   subordinate: "Shailesh  Bagde (agricultural specialist)")

    get module_path("user-hierarchy-mapping")
    assert_response :success
    assert_includes response.body, "Hemant shakkrapude",
      "the Saved Records table should list the saved head"
    assert_not_includes response.body, "No records saved yet."
  end

  test "the Cluster Incharge list shows a mapped cluster incharge" do
    create_mapping(head: "Rajkumar Pradhan (agricultural specialist)",
                   subordinate: "Jogendra Putel (Cluster Incharge)")

    get module_path("user-hierarchy-list")
    assert_response :success
    assert_includes response.body, "Jogendra Putel",
      "the mapped Cluster Incharge should be listed"
    assert_includes response.body, "Rajkumar Pradhan"
  end
end
