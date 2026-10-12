require "test_helper"

class JjReadOptimizationTest < ActiveSupport::TestCase
  test "transfer picker preserves labels and office keys without loading signatures" do
    vrp = Vrp.new(name: "Projection JJ", user_name: "projection_jj", mobile_no: "9876543210",
      fcoc: "FCO Sausar", aadhar_no: "123456789012", account_no: "123", address: "Test",
      branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "projection@example.test", experience_in_years: 0, father_husband_name: "Test",
      gender: 1, ifsc_code: "TEST0123456", office_detail_id: 0, to_office_detail_id: 0,
      agreement_signature_data: "x" * 100_000, status: 55)
    vrp.save!(validate: false)
    controller = ModulesController.new
    expected = Vrp.order(:name).where(is_active: [true, nil], is_deleted: [false, nil])
      .filter_map { |row| controller.send(:jeevika_jankar_transfer_label, row) }.uniq
    assert_equal expected, controller.send(:transferable_jeevika_jankar_options)
    rows = controller.send(:transferable_jeevika_jankar_vrps)
    assert rows.all? { |row| !row.has_attribute?(:agreement_signature_data) }
    label = controller.send(:jeevika_jankar_transfer_label, vrp)
    assert_equal AgreementVrpScope.office_key(vrp.fcoc), controller.send(:transfer_jeevika_jankar_office_keys)[label]
    controller.define_singleton_method(:vrp_login_user?) { false }
    controller.define_singleton_method(:module_mapped_vrp_scope_active?) { false }
    expected_options = Vrp.where(status: 55).order(:name).map do |row|
      [row.name.presence || row.user_name.presence || "VRP ##{row.id}", row.id.to_s]
    end
    assert_equal expected_options, controller.send(:approved_vrp_id_options)
  end

  test "shared approval channel catalogue preserves selection and tie order" do
    controller = ModulesController.new
    steps = [
      ["A", "First Approval", 1], ["B", "First Approval", 2],
      ["A", "Second Approval", 3], ["B", "Second Approval", 4],
      ["A", "First Approval", 5]
    ].map do |channel, level, id|
      ModuleRecord.new(id: id, created_at: Time.at(100), updated_at: Time.at(200), data: {
        "module_name" => "VRP Bill", "stakeholder_name" => channel,
        "user_name" => "", "approval_level" => level
      })
    end
    controller.define_singleton_method(:jeevika_bill_approval_master_steps) { steps }
    controller.define_singleton_method(:jeevika_bill_approval_step_matches_bill?) do |step, bill|
      bill.data["channels"].include?(step.data["stakeholder_name"])
    end
    [["A"], ["B"], ["A", "B"], []].each_with_index do |channels, index|
      bill = ModuleRecord.new(id: 99000 + index, data: { "channels" => channels })
      keys = steps.select { |step| controller.send(:jeevika_bill_approval_step_matches_bill?, step, bill) }
        .map { |step| controller.send(:approval_channel_key, step) }.uniq
      expected = steps.select { |step| keys.include?(controller.send(:approval_channel_key, step)) }
        .group_by { |step| controller.send(:approval_channel_key, step) }.values
        .map { |rows| controller.send(:ordered_approval_channel_steps, rows) }.reject(&:blank?)
        .max_by { |rows| controller.send(:approval_channel_priority, rows) } || []
      assert_equal expected.map(&:id), controller.send(:jeevika_bill_approval_steps, bill).map(&:id)
    end
  end

  test "observation page loads its own records only" do
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, "jeevika-jankar-observation-list")
    assert_not controller.send(:module_records_required_for_show?)
  end
end
