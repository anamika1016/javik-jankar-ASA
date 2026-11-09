require "test_helper"

class DashboardOwnerReadPerformanceTest < ActiveSupport::TestCase
  test "dashboard reuses complete signature-free owners and preloads only unresolved owners" do
    owners = [create_owner("First"), create_owner("Second")]
    targets = owners.map do |owner|
      TargetMapping.create!(vrp: owner, fco_id: "F", ics_id: "I", village_id: "V", month_name: "October",
        main_activity_name: "Training", activity_name: "Topic", target_quantity: 1)
    end
    controller = DashboardReportsController.new
    projection = controller.send(:dashboard_vrp_read_scope).find(owners.first.id)
    controller.instance_variable_set(:@dashboard_vrps, [projection])
    ids = targets.map(&:id)
    controller.define_singleton_method(:dashboard_visible_target_scope) { TargetMapping.where(id: ids) }
    instantiated = 0
    subscriber = ->(*args) { instantiated += args.last[:record_count] if args.last[:class_name] == "Vrp" }
    rows = nil
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      rows = controller.send(:dashboard_target_mappings)
    end
    assert_same projection, rows.find { |target| target.vrp_id == projection.id }.vrp
    assert_equal 1, instantiated
    rows.each do |target|
      expected = controller.send(:dashboard_vrp_read_scope).find(target.vrp_id)
      assert_equal expected.attributes, target.vrp.attributes
      assert target.association(:vrp).loaded?
      refute target.vrp.has_attribute?(:agreement_signature_data)
    end
  end

  private

  def create_owner(label)
    owner = Vrp.new(name: "Owner #{label}", aadhar_no: "123456789012", account_no: "123", address: "Address",
      branch: "Branch", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "#{label.downcase}@example.test", experience_in_years: 0, father_husband_name: "Father",
      gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0,
      agreement_signature_data: "x" * 100_000)
    owner.save!(validate: false)
    owner
  end
end
