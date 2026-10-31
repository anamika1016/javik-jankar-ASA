require "test_helper"

# A Cluster Incharge who HAS mapped Jeevika Jankars must still only see those
# Jeevika Jankars' records. The existing scope test covers a CC with no mapping
# at all; this one covers the case reported from production, where a CC mapped
# to FCO-Betul Jeevika Jankars was shown FCO-Bhawanipatna records on Training
# Form List, Other Target List and Bill List.
class ClusterInchargeMappedScopeTest < ActionDispatch::IntegrationTest
  MINE = "Ganesh Lokhande (Cluster Incharge)".freeze
  THEIRS = "Chumki Bag (Cluster Incharge)".freeze

  setup do
    ["Training Form List", "Other Target List", "Jeevika Jankar Bill"].each do |name|
      ModuleRecord.create!(module_slug: "access-control", data: {
        "sub_module_names" => [name], "can_view" => "Yes", "status" => "Active"
      })
    end

    @my_jj = jeevika_jankar("Rukmini Mahi", MINE, "FCO-Betul", "9800000001")
    @their_jj = jeevika_jankar("Jyosnamayi Suna", THEIRS, "FCO-Bhawanipatna", "9800000002")

    @my_record = ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "select_vrp" => @my_jj.id.to_s,
      "fco_name" => "FCO-Betul", "gram_name" => "BETUL_MINE_RECORD",
      "trainer_name" => "Betul Trainer"
    })
    @their_record = ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "select_vrp" => @their_jj.id.to_s,
      "fco_name" => "FCO-Bhawanipatna", "gram_name" => "BHAWANIPATNA_OTHER_RECORD",
      "trainer_name" => "Jodabandh Trainer"
    })

    @cc = User.create!(user_name: "ganesh_cc", password: "secret",
      first_name: "Ganesh", last_name: "Lokhande", role: "Cluster Incharge",
      office_name: "FCO-Betul", user_type: "User", status: "Active")
  end

  def jeevika_jankar(name, cluster_label, fcoc, mobile)
    Vrp.create!(
      name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: mobile + "12", account_no: mobile, bank_name: "B", branch: "Br",
      ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "#{name.parameterize}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret",
      cluster_incharge: cluster_label, fcoc: fcoc
    )
  end

  def login_as_cc
    post login_path, params: { login: @cc.user_name, password: "secret" }
  end

  test "a mapped cluster incharge does not see another cluster's training records" do
    login_as_cc

    get module_path("training-form-list")

    assert_response :success
    assert_not_includes response.body, "BHAWANIPATNA_OTHER_RECORD",
      "the cluster incharge was shown a Jeevika Jankar mapped to a different cluster"
  end

  test "a mapped cluster incharge still sees their own cluster's training records" do
    login_as_cc

    get module_path("training-form-list")

    assert_response :success
    assert_includes response.body, "BETUL_MINE_RECORD",
      "the cluster incharge lost sight of their own mapped Jeevika Jankar"
  end

  # The production screenshot shows the leaked rows with "Cluster Coordinator
  # Name: N/A", so the suspect is a training record that names no Jeevika
  # Jankar at all and therefore belongs to no cluster.
  test "a training record with no Jeevika Jankar is not shown to a cluster incharge" do
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "fco_name" => "FCO-Bhawanipatna",
      "gram_name" => "UNATTRIBUTED_RECORD", "trainer_name" => "Jyosnamayi Suna"
    })

    login_as_cc
    get module_path("training-form-list")

    assert_response :success
    assert_not_includes response.body, "UNATTRIBUTED_RECORD",
      "a training record belonging to no cluster was shown to a cluster incharge"
  end

  test "a record whose Jeevika Jankar has no cluster label is not shown either" do
    orphan = jeevika_jankar("Orphan JJ", "", "FCO-Bhawanipatna", "9800000003")
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "select_vrp" => orphan.id.to_s,
      "fco_name" => "FCO-Bhawanipatna", "gram_name" => "BLANK_CLUSTER_RECORD",
      "trainer_name" => "Jyosnamayi Suna"
    })

    login_as_cc
    get module_path("training-form-list")

    assert_response :success
    assert_not_includes response.body, "BLANK_CLUSTER_RECORD",
      "a Jeevika Jankar with no cluster label leaked into a cluster incharge's list"
  end

  test "the visible Jeevika Jankar set is exactly the mapped cluster" do
    login_as_cc
    get module_path("training-form-list")

    controller = @controller
    visible = controller.send(:module_cluster_visible_vrps).map(&:id)

    assert_includes visible, @my_jj.id
    assert_not_includes visible, @their_jj.id,
      "a Jeevika Jankar from another cluster leaked into the visible set"
  end
end
