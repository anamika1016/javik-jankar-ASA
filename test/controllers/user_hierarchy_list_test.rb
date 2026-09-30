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

  # Not every saved label carries "(Cluster Incharge)"; the role then has to come
  # from the registered User, exactly as every other screen resolves it.
  test "a subordinate saved without the role suffix is still listed" do
    User.create!(user_name: "plain_cc", password: "secret", first_name: "Lilabati",
                 last_name: "Bhoi", role: "Cluster Incharge", status: "Active")
    create_mapping(head: "Sangam Kumari (Manager ics)", subordinate: "Lilabati Bhoi")

    get module_path("user-hierarchy-list")
    assert_response :success
    assert_includes response.body, "Lilabati Bhoi",
      "a Cluster Incharge without the role suffix should still be listed"
  end

  test "a subordinate who is not a cluster incharge stays out of the list" do
    User.create!(user_name: "plain_agro", password: "secret", first_name: "Bimal",
                 last_name: "Pradhan", role: "Agronomist", status: "Active")
    create_mapping(head: "Akash Mandal (FCO-C Turekela)", subordinate: "Bimal Pradhan")

    get module_path("user-hierarchy-list")
    assert_response :success
    assert_not_includes response.body, "Bimal Pradhan",
      "a non cluster incharge must not appear in the Cluster Incharge list"
  end
end
