require "test_helper"

# Admin sees every FCO's farmer master; a posted user only ever sees their own
# FCO. There is no hard-coded FCO list anywhere in this path.
class DashboardFcoVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    ModuleRecord.create!(module_slug: "access-control", data: {
      "sub_module_names" => ["Dashboard"], "can_view" => "Yes", "status" => "Active"
    })

    # Three different offices, including one that is neither Sausar nor Turekela
    # so a hard-coded pair would be caught.
    afl("1004", "Sausar",       "ics-s", "vil-s", "TRC-S")
    afl("1006", "Turekela",     "ics-t", "vil-t", "TRC-T")
    afl("995",  "Bhawanipatna", "ics-b", "vil-b", "TRC-B")
  end

  def afl(fco_id, fco, ics, village, tracenet)
    Afl.create!(fco_id: fco_id, fco: fco, ics_id: ics, ics_name: "ICS #{fco}",
                village_id: village, village_name: "V #{fco}",
                farmer_name: "F #{fco}", tracenet_no: tracenet)
  end

  def counts_for(controller)
    %i[ics village farmer].to_h do |kind|
      [kind, controller.send(:dashboard_total_afl_distinct_count, kind)]
    end
  end

  def controller_for(office:, admin:)
    c = ModulesController.new
    c.define_singleton_method(:model_ready?) { |_| true }
    c.define_singleton_method(:dashboard_filter_param) { |*| nil }
    c.define_singleton_method(:admin_dashboard_user?) { admin }
    c.define_singleton_method(:dashboard_global_view_user?) { admin }
    c.define_singleton_method(:dashboard_summary_fco_filter_values) do |*|
      admin ? [] : [office.to_s.downcase]
    end
    c.instance_variable_set(:@dashboard_fcoc_filter_value, admin ? nil : office)
    c
  end

  test "an admin sees every FCO in the farmer master" do
    counts = counts_for(controller_for(office: nil, admin: true))
    assert_equal 3, counts[:ics], "admin should see all three offices' ICS"
    assert_equal 3, counts[:village]
    assert_equal 3, counts[:farmer]
  end

  test "a posted user only sees their own FCO" do
    counts = counts_for(controller_for(office: "FCO-C Turekela", admin: false))
    assert_equal 1, counts[:ics], "a Turekela login should only see Turekela"
    assert_equal 1, counts[:village]
    assert_equal 1, counts[:farmer]
  end

  # The office is spelled differently across the app; every spelling has to
  # resolve, and it must work for any FCO, not a fixed pair.
  test "every office spelling resolves, for any FCO" do
    ["FCO-Bhawanipatna", "Bhawanipatna - FCO", "FCO-C Bhawanipatna", "Bhawanipatna"].each do |spelling|
      counts = counts_for(controller_for(office: spelling, admin: false))
      assert_equal 1, counts[:farmer], "#{spelling.inspect} should resolve to Bhawanipatna"
    end
  end

  test "one office's login never sees another office's rows" do
    sausar = counts_for(controller_for(office: "FCO-C Sausar", admin: false))
    assert_equal 1, sausar[:farmer]

    scope = controller_for(office: "FCO-C Sausar", admin: false)
      .send(:dashboard_total_afl_farmer_scope)
    assert_equal ["1004"], scope.distinct.pluck(:fco_id)
  end
end
