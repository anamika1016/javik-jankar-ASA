require "test_helper"

# The "Main Major Work Indicator - Other" box has a View List drill-down. Admin
# sees every FCO's entries; a posted user only sees their own office.
class OtherIndicatorListTest < ActionDispatch::IntegrationTest
  setup do
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active"
    })
    # The dashboard defaults to the current month, so the rows live there.
    @month = Date.current.strftime("%B")
    other_target("Sausar JJ", "FCO-C Sausar", @month, "Seed Distribution")
    other_target("Patna JJ", "FCO-Bhawanipatna", @month, "Input Demo")
  end

  def other_target(jj, fcoc, month, activity)
    ModuleRecord.create!(module_slug: "other-target", data: {
      "jeevika_jankar_name" => jj, "fcoc_name" => fcoc, "month" => month,
      "main_activity" => activity, "sub_activity" => "Sub", "target" => "10",
      "achievement" => "4", "status" => "Active"
    })
  end

  def login_admin
    User.create!(user_name: "oil_admin", password: "secret", first_name: "Adm",
                 user_type: "admin", status: "Active")
    post login_path, params: { login: "oil_admin", password: "secret" }
  end

  test "the dashboard links to the drill-down list" do
    login_admin
    get dashboard_path
    assert_response :success
    assert_includes response.body, other_indicator_list_path
  end

  test "an admin sees every office's Other entries" do
    login_admin
    get other_indicator_list_path
    assert_response :success
    assert_includes response.body, "Sausar JJ"
    assert_includes response.body, "Patna JJ"
  end

  test "the list exports to xlsx" do
    login_admin
    get other_indicator_list_path(format: :xlsx)
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      response.media_type
  end

  test "the month filter narrows the rows" do
    other_month = Date.current.prev_month.strftime("%B")
    other_target("Last Month JJ", "FCO-C Sausar", other_month, "Input Demo")
    login_admin

    get other_indicator_list_path(month: other_month)
    assert_response :success
    assert_includes response.body, "Last Month JJ"
    assert_not_includes response.body, "Sausar JJ",
      "a row from a different month must not appear"
  end

  # The office is spelled "FCO-Bhawanipatna" on the record but a login may carry
  # "Bhawanipatna"; both have to resolve to the same office.
  test "an FCO filter matches whichever spelling the record used" do
    login_admin
    get other_indicator_list_path(fcoc: "Bhawanipatna")
    assert_response :success
    assert_includes response.body, "Patna JJ"
    assert_not_includes response.body, "Sausar JJ",
      "another office's entry must not appear under this FCO filter"
  end
end
