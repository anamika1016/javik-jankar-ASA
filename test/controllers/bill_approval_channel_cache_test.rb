require "test_helper"

# jeevika_bill_approval_steps decides which approval channel a bill belongs to
# by scanning every approval-master channel. A bill list is mostly bills that
# share a cluster incharge or creator, so the same identity set was scanned
# against every channel once per bill - O(bills x channels) on a screen that
# renders hundreds of rows.
#
# The scan is driven entirely by the bill's approval identities, which is now
# stated in jeevika_bill_approval_step_matches_identities?'s signature, so the
# result is kept against those identities. These tests pin that bills with
# equal identities still agree, that bills with different identities are kept
# apart, and that the shared memo cannot hand one bill another bill's channel.
class BillApprovalChannelCacheTest < ActiveSupport::TestCase
  # Only the identities are stubbed - the real matcher and the real channel
  # ordering run, so this exercises the production path.
  class StubbedController < ModulesController
    attr_accessor :identities_by_record_id, :identity_calls

    def initialize
      super
      @identity_calls = 0
    end

    def jeevika_bill_approval_identities(record)
      @identity_calls += 1
      identities_by_record_id.fetch(record.id, [])
    end
    public :jeevika_bill_approval_steps
  end

  setup do
    # approval_channel_key is [module_name, stakeholder_name, user_name], so the
    # user_name is what makes these two separate channels rather than two
    # levels of one channel.
    @ranapur = channel_step("FCO-Ranapur", "pritesh")
    @jobat = channel_step("FCO-Jobat", "sadik")

    @bill_a = bill
    @bill_b = bill
    @bill_c = bill
  end

  def channel_step(office, user_name)
    ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Bill", "approval_level" => "First Approval",
      "stakeholder_name" => "ASA", "sub_office_name" => office,
      "user_name" => user_name, "approver_approved_by" => user_name
    })
  end

  def bill
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process",
      data: { "bill_month" => "October" })
  end

  def identity(office, user_name)
    { stakeholder: "ASA", office: office, office_category: nil,
      user_name: user_name, user_names: [user_name] }
  end

  def ranapur_identity = identity("FCO-Ranapur", "pritesh")
  def jobat_identity = identity("FCO-Jobat", "sadik")

  def controller_with(map)
    controller = StubbedController.new
    controller.identities_by_record_id = map
    controller
  end

  test "bills with equal identities resolve to the same channel" do
    controller = controller_with(@bill_a.id => [ranapur_identity],
      @bill_b.id => [ranapur_identity])

    assert_equal [@ranapur.id], controller.jeevika_bill_approval_steps(@bill_a).map(&:id)
    assert_equal controller.jeevika_bill_approval_steps(@bill_a).map(&:id),
      controller.jeevika_bill_approval_steps(@bill_b).map(&:id)
  end

  test "bills with different identities are kept apart" do
    controller = controller_with(@bill_a.id => [ranapur_identity],
      @bill_b.id => [jobat_identity])

    assert_equal [@ranapur.id], controller.jeevika_bill_approval_steps(@bill_a).map(&:id)
    assert_equal [@jobat.id], controller.jeevika_bill_approval_steps(@bill_b).map(&:id),
      "the shared memo handed the first bill's channel to a bill with different identities"
  end

  test "the shared memo gives the same answer a per-bill scan would" do
    map = { @bill_a.id => [ranapur_identity], @bill_b.id => [jobat_identity],
            @bill_c.id => [ranapur_identity] }
    shared = controller_with(map)
    shared_result = [@bill_a, @bill_b, @bill_c].map { |b| shared.jeevika_bill_approval_steps(b).map(&:id) }

    # A fresh controller per bill cannot reuse anything, so this is the answer
    # the unmemoised scan produces.
    isolated = [@bill_a, @bill_b, @bill_c].map do |b|
      controller_with(b.id => map[b.id]).jeevika_bill_approval_steps(b).map(&:id)
    end

    assert_equal isolated, shared_result
  end

  test "a bill with no identities matches no channel" do
    controller = controller_with(@bill_a.id => [])

    assert_empty controller.jeevika_bill_approval_steps(@bill_a)
  end

  test "an empty identity set does not borrow another bill's channel" do
    controller = controller_with(@bill_a.id => [ranapur_identity], @bill_b.id => [])

    assert_equal [@ranapur.id], controller.jeevika_bill_approval_steps(@bill_a).map(&:id)
    assert_empty controller.jeevika_bill_approval_steps(@bill_b),
      "a bill with no identities picked up a channel from the shared memo"
  end

  test "repeat lookups for one bill still answer from the per-bill cache" do
    controller = controller_with(@bill_a.id => [ranapur_identity])
    controller.jeevika_bill_approval_steps(@bill_a)
    calls_after_first = controller.identity_calls

    3.times { controller.jeevika_bill_approval_steps(@bill_a) }

    assert_equal calls_after_first, controller.identity_calls,
      "the per-bill cache stopped short-circuiting, so the work is being redone"
  end

  test "the scan runs once per distinct identity set, not once per bill" do
    controller = controller_with(@bill_a.id => [ranapur_identity],
      @bill_b.id => [ranapur_identity], @bill_c.id => [jobat_identity])

    [@bill_a, @bill_b, @bill_c].each { |b| controller.jeevika_bill_approval_steps(b) }

    cache = controller.instance_variable_get(:@jeevika_bill_matching_channel_keys_cache)
    assert_equal 2, cache.size,
      "three bills over two identity sets should have scanned the channels twice"
  end
end
