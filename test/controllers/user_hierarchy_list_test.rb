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

  # The list's Edit/Delete buttons act on the checkbox value, which is the
  # record's edit path (Delete strips the trailing "/edit").
  test "the row exposes a working edit path and the edit screen is prefilled" do
    record = create_mapping(head: "Akash Mandal (FCO-C Turekela)",
                            subordinate: "Jogendra Putel (Cluster Incharge)")
    edit_path = "/modules/user-hierarchy-mapping/records/#{record.id}/edit"

    get module_path("user-hierarchy-list")
    assert_includes response.body, edit_path, "the row checkbox should carry the edit path"

    get edit_path
    assert_response :success
    assert_includes response.body, "Akash Mandal", "the edit screen should prefill the saved head"
  end

  test "deleting from the list removes the mapping" do
    record = create_mapping(head: "Akash Mandal (FCO-C Turekela)",
                            subordinate: "Jogendra Putel (Cluster Incharge)")

    assert_difference -> { ModuleRecord.where(module_slug: "user-hierarchy-mapping").count }, -1 do
      delete "/modules/user-hierarchy-mapping/records/#{record.id}"
    end
    assert_nil ModuleRecord.find_by(id: record.id)
  end

  # A head with many subordinates still has to render its own columns; a tall
  # row previously pushed them out of the scrolling table.
  test "a head with many subordinates still renders head, category and status" do
    subs = (1..9).map { |i| "CC Person #{i} (Cluster Incharge)" }
    ModuleRecord.create!(module_slug: "user-hierarchy-mapping", data: {
      "stakeholder_category" => "PAPL",
      "level_1_user" => "Akash Mandal (FCO-C Turekela)",
      "status" => "Active",
      "level_2_mappings" => subs.map { |s| { "level_2_user" => s, "level_3_users" => [] } },
      "level_2_users" => subs, "level_2_user" => subs.join(", ")
    })

    get module_path("user-hierarchy-list")
    assert_response :success
    assert_includes response.body, "Akash Mandal"
    assert_includes response.body, "PAPL"
    assert_select "##{'user_hierarchy_list_table'} tbody .status-pill", minimum: 1
    assert_equal 9, response.body.scan(/Subordinate \d+/).size
  end

  # Any mapped subordinate is listed, whatever their role, so a saved mapping is
  # never silently missing from the screen that lists mappings.
  test "a subordinate of any role is listed" do
    create_mapping(head: "Akashdeep Nath (FCO-Pakur)",
                   subordinate: "Mohanlal Saha (Agrinomist)")

    get module_path("user-hierarchy-list")
    assert_response :success
    assert_includes response.body, "Mohanlal Saha",
      "an Agronomist subordinate should be listed"
    assert_includes response.body, "Akashdeep Nath"
  end

  test "cluster incharge and other roles appear together" do
    create_mapping(head: "Akash Mandal (FCO-C Turekela)",
                   subordinate: "Jagadish Putel (Cluster Incharge)")
    create_mapping(head: "Akashdeep Nath (FCO-Pakur)",
                   subordinate: "Mohanlal Saha (Agrinomist)")

    get module_path("user-hierarchy-list")
    assert_response :success
    assert_includes response.body, "Jagadish Putel"
    assert_includes response.body, "Mohanlal Saha"
  end
end
