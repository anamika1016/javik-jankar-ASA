require "test_helper"

class JeevikaBillResubmissionTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    @bill = ModuleRecord.new(id: 180472, data: { "status" => "Pending at First" })
    @steps = ["First", "Second"].map do |level|
      ModuleRecord.new(data: { "approval_level" => "#{level} Approval", "approver_approved_by" => level })
    end
    steps = @steps
    @history = []
    history = @history
    @controller.define_singleton_method(:jeevika_bill_approval_steps) { |_| steps }
    @controller.define_singleton_method(:jeevika_bill_approval_history) { |_| history }
  end

  test "resubmission reopens first approver after rejection or return and preserves audit history" do
    %w[Rejected Returned].each do |action|
      @history.replace([entry("Sent for Approval"), entry("Approved"), entry(action, "Second"), entry("Sent for Approval")])
      @controller.instance_variable_set(:@jeevika_bill_current_approval_step_cache, {})
      assert_equal @steps.first, @controller.send(:jeevika_bill_current_approval_step, @bill)
      assert_empty @controller.send(:jeevika_bill_approved_sequences, @bill)
      assert_empty @controller.send(:jeevika_bill_current_approval_history, @bill)
      assert_equal 4, @controller.send(:jeevika_bill_approval_history, @bill).size
    end
  end

  test "approval in the new submission advances to second approver" do
    @history.concat([entry("Rejected"), entry("Sent for Approval"), entry("Approved")])
    assert_equal @steps.last, @controller.send(:jeevika_bill_current_approval_step, @bill)
    assert_equal [1], @controller.send(:jeevika_bill_approved_sequences, @bill)
  end

  test "legacy history without a submission marker still closes approved steps" do
    @history << entry("Approved")
    assert_equal @steps.last, @controller.send(:jeevika_bill_current_approval_step, @bill)
  end

  private

  def entry(action, level = "First")
    ModuleRecord.new(data: { "action" => action, "approval_level" => "#{level} Approval", "approver" => level })
  end
end
