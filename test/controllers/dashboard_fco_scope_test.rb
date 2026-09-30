require "test_helper"

# AFL rows store the bare FCO name ("Bhawanipatna") while a login's office is
# spelled "FCO-C Sausar", "FCO-Bhawanipatna" or "Bhawanipatna - FCO". Every
# spelling has to resolve to the same FCO, for any office, with no hard-coded
# FCO list anywhere.
class DashboardFcoScopeTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    @controller.define_singleton_method(:model_ready?) { |_| true }

    Afl.create!(fco_id: "995", fco: "Bhawanipatna", ics_id: "1", ics_name: "ICS A",
                village_id: "11", village_name: "V1", farmer_name: "F1", tracenet_no: "T1")
    Afl.create!(fco_id: "1004", fco: "Sausar", ics_id: "2", ics_name: "ICS B",
                village_id: "22", village_name: "V2", farmer_name: "F2", tracenet_no: "T2")
    # An office that only ever appears with the "FCO-C " prefix in AFL itself.
    Afl.create!(fco_id: "1006", fco: "Turekela", ics_id: "3", ics_name: "ICS C",
                village_id: "33", village_name: "V3", farmer_name: "F3", tracenet_no: "T3")
  end

  def ids_for(*values)
    @controller.send(:dashboard_afl_fco_ids_for, values)
  end

  test "every spelling of one office resolves to the same AFL fco_id" do
    ["FCO-Bhawanipatna", "Bhawanipatna - FCO", "FCO-C Bhawanipatna", "Bhawanipatna", "995"]
      .each do |spelling|
        assert_equal ["995"], ids_for(spelling),
          "#{spelling.inspect} should resolve to the Bhawanipatna FCO"
      end
  end

  test "it works for any office, not a hard-coded list" do
    assert_equal ["1004"], ids_for("FCO-C Sausar")
    assert_equal ["1006"], ids_for("FCO-C Turekela")
    assert_equal ["995"], ids_for("FCO-Bhawanipatna")
  end

  test "an office with no AFL data resolves to nothing instead of matching another FCO" do
    assert_empty ids_for("FCO-Pakur")
    assert_empty ids_for("")
    assert_empty ids_for("NULL")
  end

  test "several offices resolve together" do
    assert_equal %w[995 1004].sort, ids_for("FCO-Bhawanipatna", "FCO-C Sausar").sort
  end

  # The regression: a Bhawanipatna login used to see 0 because "FCO-Bhawanipatna"
  # never matched AFL's "Bhawanipatna".
  test "the farmer scope returns rows for an FCO- prefixed office" do
    @controller.instance_variable_set(:@dashboard_fcoc_filter_value, "FCO-Bhawanipatna")
    @controller.define_singleton_method(:dashboard_filter_param) { |*| nil }
    @controller.define_singleton_method(:dashboard_summary_fco_filter_values) do |*|
      ["fco-bhawanipatna"]
    end

    scope = @controller.send(:dashboard_total_afl_farmer_scope)
    assert_equal 1, scope.count, "a Bhawanipatna login must not see a zero farmer count"
    assert_equal "995", scope.first.fco_id
  end
end
