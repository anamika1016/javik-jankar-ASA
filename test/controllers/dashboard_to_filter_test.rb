require "test_helper"

# A TO belongs to one FCO. The dashboard listed every TO before an FCO was
# chosen, so an admin saw a dropdown of options that mostly matched nothing.
class DashboardToFilterTest < ActiveSupport::TestCase
  setup do
    ModuleRecord.create!(module_slug: "office-mapping-add", data: {
      "office_category" => "FCO-Bhawanipatna", "sub_office_name" => "TO-Narla", "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "office-mapping-add", data: {
      "office_category" => "FCO-Bhawanipatna", "sub_office_name" => "TO-Kesinga", "status" => "Active"
    })
    ModuleRecord.create!(module_slug: "office-mapping-add", data: {
      "office_category" => "FCO-Sausar", "sub_office_name" => "TO-Barhait", "status" => "Active"
    })
  end

  test "an admin with no FCO chosen is offered no TO, not every TO" do
    options = to_options_for(global: true, fco: nil)

    assert_empty options, "the TO list must wait for an FCO"
  end

  test "choosing an FCO offers only that FCO's TOs" do
    options = to_options_for(global: true, fco: "FCO-Bhawanipatna")

    assert_equal ["TO-Kesinga", "TO-Narla"], options
    assert_not_includes options, "TO-Barhait"
  end

  test "a TO already selected stays listed so the dropdown shows what is filtering" do
    options = to_options_for(global: true, fco: nil, to: "TO-Narla")

    assert_equal ["TO-Narla"], options
  end

  test "a user scoped to one office still sees their own TOs without choosing an FCO" do
    options = to_options_for(global: false, fco: nil, office_keys: [AgreementVrpScope.office_key("FCO-Sausar")])

    assert_equal ["TO-Barhait"], options
  end

  private

  def to_options_for(global:, fco:, to: nil, office_keys: [])
    controller = DashboardReportsController.new
    controller.instance_variable_set(:@dashboard_fcoc_filter_value, fco)
    controller.define_singleton_method(:dashboard_global_view_user?) { global }
    controller.define_singleton_method(:dashboard_current_user_office_keys) { office_keys }
    controller.define_singleton_method(:dashboard_filter_param) do |*keys|
      keys.include?(:to_name) ? to : fco
    end
    controller.define_singleton_method(:active_module_record?) { |_record| true }

    controller.send(:dashboard_to_options)
  end
end
