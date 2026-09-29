require "test_helper"

# The approver's sidebar must advertise a waiting training edit even while the
# parent menu is collapsed, which is the state on every page except the list
# itself.
class SidebarPendingDotTest < ActionDispatch::IntegrationTest
  setup do
    # Blank role fields match any login, so the menu renders for both users here.
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Training Form List"], "can_view" => "Yes", "status" => "Active"
    })
    @approver = User.create!(
      user_name: "sidebar_dot_agronomist", password: "secret", first_name: "Sidebar",
      last_name: "Approver", role: "Agronomist", office_name: "FCO-C Sausar"
    )
    @record = ModuleRecord.create!(module_slug: "training-form", data: {
      "fco_name" => "FCO-C Sausar", "month" => "July", "training_location" => "Original"
    })
    @revision = TrainingEditApproval.submit!(
      record: @record,
      proposed: @record.data.merge("training_location" => "Changed"),
      actor: { "id" => "90901", "record_type" => "User", "username" => "sidebar_dot_cc" }
    )
    post login_path, params: { login: @approver.user_name, password: "secret" }
  end

  # The dashboard leaves "Farmer Target" collapsed, so only a dot on the parent
  # summary is actually visible to the approver there.
  test "parent menu carries the pending dot on a page that collapses it" do
    get dashboard_path
    assert_response :success

    summary = css_select("details.side-module > summary").find do |node|
      node.text.include?("Farmer Target")
    end
    assert summary, "Farmer Target section should render for the approver"
    assert summary.css(".side-pending-dot").any?,
      "collapsed parent menu should still show the pending dot"
  end

  test "dot survives a repeat load and clears once the edit is approved" do
    2.times do
      get dashboard_path
      assert_select "details.side-module > summary .side-pending-dot", minimum: 1
    end

    TrainingEditApproval.decide!(
      revision: @revision,
      actor: { "id" => @approver.id, "record_type" => "User", "username" => @approver.user_name },
      decision: "approve", remarks: "Verified"
    )

    get dashboard_path
    assert_select "details.side-module > summary .side-pending-dot", count: 0
  end

  test "a user with nothing pending never gets a dot" do
    other = User.create!(
      user_name: "sidebar_dot_bystander", password: "secret", first_name: "By",
      last_name: "Stander", role: "Agronomist", office_name: "FCO-C Turekela"
    )
    post login_path, params: { login: other.user_name, password: "secret" }

    get dashboard_path
    assert_select ".side-pending-dot", count: 0
  end
end
