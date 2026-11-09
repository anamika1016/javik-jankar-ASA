require "test_helper"

class OtherTargetFormReadTest < ActiveSupport::TestCase
  test "both other target forms retain complete mapping output while preloading only eligible targets" do
    owner = Vrp.new(name: "Header JJ", mobile_no: "9876543210", aadhar_no: "123456789012",
      account_no: "123", address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1),
      date_of_joining: Date.current, email: "header-jj@example.test", experience_in_years: 0,
      father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456", office_detail_id: 0, to_office_detail_id: 0)
    owner.save!(validate: false)
    targets = %w[Train Other Farmer Unknown].map do |activity|
      TargetMapping.create!(vrp: owner, fco_id: "F", ics_id: "I", village_id: "V",
        month_name: "November", main_activity_name: activity, activity_name: "Work",
        target_quantity: 2, afl_ids: ["1", "2"])
    end
    settings = { "train" => { main_activity_type: "Training" }, "other" => { main_activity_type: "Other" },
      "farmer" => { main_activity_type: "Other with Farmer" } }
    build = lambda do |slug, observed|
      controller = ModulesController.new
      controller.define_singleton_method(:record_source_slug) { slug }
      controller.define_singleton_method(:jeevika_jankar_main_activity_settings) { settings }
      controller.define_singleton_method(:jeevika_jankar_sub_activity_settings) { |_| {} }
      controller.define_singleton_method(:training_target_scope) { TargetMapping.where(id: targets.map(&:id)) }
      controller.define_singleton_method(:preload_target_vrps!) do |rows|
        observed.concat(rows.map(&:id))
        rows
      end
      controller.define_singleton_method(:registered_vrp_fcoc) { |_| "F" }
      controller.define_singleton_method(:preload_other_target_completed_farmer_ids!) { |_| nil }
      controller.define_singleton_method(:other_with_farmer_target_exhausted?) { |_| false }
      controller.define_singleton_method(:other_target_completed_farmer_ids_for) { |_| ["1"] }
      controller
    end
    %w[other-target other-target-with-farmer].each do |slug|
      baseline = nil
      original_filter = TargetFormReadQuery.method(:filter)
      begin
        TargetFormReadQuery.define_singleton_method(:filter) { |scope, &_| scope }
        baseline = build.call(slug, []).send(:build_seed_distribution_target_mappings)
      ensure
        TargetFormReadQuery.define_singleton_method(:filter, original_filter)
      end
      observed = []
      actual = build.call(slug, observed).send(:build_seed_distribution_target_mappings)
      assert_equal baseline, actual
      assert_equal [targets[slug == "other-target" ? 1 : 2].id], observed
      assert_equal 1, actual.size
    end
  end
end
