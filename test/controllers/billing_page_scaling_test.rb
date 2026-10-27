require "test_helper"

class BillingPageScalingTest < ActiveSupport::TestCase
  test "read batch preserves canonical aliases scope fallbacks and SQL ordering" do
    first = owner(1)
    second = owner(2)
    [first, second].each do |vrp|
      ["October", "10", "Oct", "\tOctober\t", "September", "Unknown"].each_with_index do |month, i|
        target(vrp, month, i)
      end
    end
    months = ["October", "10", "Oct", "September", "invalid-month", ""]
    controller = calculator([first.id])
    batch = BillTargetReadBatch.new(owner_ids: [first.id, second.id, 99999999], months: months, month_number: controller.method(:month_number_value))
    [nil, [], [first.id]].each do |visible|
      c = calculator(visible)
      [[first.id.to_s], [second.id.to_s], [first.id.to_s, second.id.to_s], ["0#{first.id}"], ["99999999"]].each do |ids|
        months.each do |month|
          expected = c.send(:jeevika_jankar_bill_target_records, selected_vrp_ids: ids, vrp_id: ids.join(","), month_name: month)
          actual = batch.records_for(owner_ids: ids, month: month, scoped_owner_ids: visible)
          assert_equal expected.map(&:attributes), actual.map(&:attributes), "scope=#{visible.inspect}, owners=#{ids}, month=#{month.inspect}"
        end
      end
    end
  end

  test "scoped live totals equal individual calculation with fewer target reads" do
    owners = 12.times.map { |i| owner(10 + i) }
    ModuleRecord.create!(module_slug: "add-activity-group", data: { "main_activity_name" => "Training", "main_activity_type" => "Training" })
    bills = owners.each_with_index.map do |vrp, i|
      month = i % 3 == 0 ? "10" : "October"
      t = target(vrp, month, i)
      farmer = Afl.create!(farmer_name: "Farmer #{i}", fco_id: "F", ics_id: "I", village_id: "V")
      t.update!(afl_ids: [farmer.id])
      ModuleRecord.create!(module_slug: "training-form", data: { "jeevika_jankar_id" => vrp.id.to_s,
        "month" => month, "main_activity" => "Training", "sub_activity" => "Work", "target_mapping_id" => t.id.to_s,
        "selected_farmer_ids" => [farmer.id.to_s], "main_activity_type" => "Training", "ics_block" => "I", "gram_name" => "V",
        "farmer_count" => "1", "male_count" => "1", "female_count" => "0", "total_farmer_count" => "1",
        "training_method" => "OPG Training", "training_date" => "2026-10-02" })
      ModuleRecord.new(data: { "select_vrp" => vrp.id.to_s, "bill_month" => "October", "total_target" => "99", "total_achievement" => "88" })
    end
    old = calculator(owners.first(4).map(&:id))
    before = nil
    before_sql = capture { before = bills.map { |bill| totals(old, bill) } }
    optimized = calculator(owners.first(4).map(&:id))
    after = nil
    after_sql = capture do
      optimized.send(:preload_jeevika_bill_process_totals, bills)
      after = bills.map { |bill| totals(optimized, bill) }
    end
    assert_equal before, after
    assert before.any? { |pair| pair.first.to_f == 1 && pair.last.to_f == 1 }
    assert_operator after_sql.count { |sql| sql.include?('FROM "target_mappings"') }, :<,
      before_sql.count { |sql| sql.include?('FROM "target_mappings"') }
    refute optimized.instance_variable_get(:@jeevika_bill_target_read_batch)
    refute optimized.instance_variable_get(:@jeevika_bill_totals_progress_only)
  end

  test "totals skip weekly display work and dashboard calls retain it" do
    vrp = owner(40)
    target(vrp, "October", 1)
    c = calculator(nil)
    c.define_singleton_method(:training_weekly_achievement_farmer_ids) { |*| raise "Weekly display path" }
    c.send(:jeevika_jankar_bill_rows, vrp_id: vrp.id.to_s, month_name: "October", totals_only: true)
    assert_raises(RuntimeError) { c.send(:vrp_dashboard_target_progress_rows, TargetMapping.where(vrp_id: vrp.id).to_a, []) }
    refute c.instance_variable_get(:@jeevika_bill_totals_progress_only)
  end

  test "identity lookup preserves precedence and stops before scanning bill items" do
    c = calculator(nil)
    preferred = owner(50)
    fallback = owner(51)
    c.define_singleton_method(:cached_vrp_lookup) { |value| { preferred.id.to_s => preferred, fallback.id.to_s => fallback }[value.to_s] }
    bill = ModuleRecord.new(data: { "select_vrp" => preferred.id.to_s, "bill_items" => [{ "vrp_id" => fallback.id.to_s }] })
    c.define_singleton_method(:jeevika_bill_detail_rows) { |_| raise "Unused items" }
    assert_same preferred, c.send(:jeevika_bill_vrp, bill)
  end

  test "payment date options load only unpaid histories and other histories remain readable" do
    paid = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Final Approved", "bill_month" => "October" })
    unpaid = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Final Approved", "bill_month" => "October" })
    histories = [paid, unpaid].map do |bill|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: { "bill_id" => bill.id.to_s,
        "action" => "Approved", "action_at" => "2026-10-20T10:00:00Z" })
    end
    c = calculator(nil)
    c.define_singleton_method(:jeevika_paid_bill_ids) { [paid.id.to_s] }
    queries = capture do
      2.times { assert_equal ["2026-10-20"], c.send(:jeevika_payment_bill_date_options, [paid, unpaid]) }
    end
    assert_equal 1, queries.size
    partial = c.instance_variable_get(:@jeevika_payment_history_by_bill_id)
    assert_equal [unpaid.id.to_s], partial.keys
    assert_equal [histories.last.id], partial[unpaid.id.to_s].map(&:id)
    assert_equal [histories.first.id], c.send(:jeevika_bill_approval_history, paid).map(&:id)
  end

  test "completed payment records reuse already loaded rows in original newest order" do
    first = ModuleRecord.create!(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG,
      created_at: 1.day.ago, data: { "payment_items" => [{ "name" => "Old" }] })
    second = ModuleRecord.create!(module_slug: ModulesController::JEEVIKA_JANKAR_PAYMENT_DETAIL_SLUG,
      data: { "payment_items" => [{ "name" => "New" }] })
    c = calculator(nil)
    c.instance_variable_set(:@slug, "jeevika-jankar-completed-payment-list")
    c.instance_variable_set(:@records, [first, second])
    queries = capture { assert_equal [second.id, first.id], c.send(:jeevika_payment_detail_records).map(&:id) }
    assert_empty queries
  end

  test "payment history prefetch retains the existing visible-bill restriction" do
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Final Approved" })
    ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: { "bill_id" => bill.id.to_s, "action" => "Approved" })
    c = calculator(nil)
    c.instance_variable_set(:@jeevika_bill_visible_record_ids, [])
    queries = capture { c.send(:preload_jeevika_payment_bill_histories!, [bill]) }
    assert_empty queries
    assert_empty c.send(:jeevika_bill_approval_history, bill)
  end

  test "payment rows preload history only for the displayed month" do
    october = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "status" => "Final Approved", "bill_month" => "October"
    })
    september = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "status" => "Final Approved", "bill_month" => "September"
    })
    [october, september].each do |bill|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: {
        "bill_id" => bill.id.to_s, "action" => "Approved"
      })
    end
    c = calculator(nil)
    c.instance_variable_set(:@jeevika_bill_visible_record_ids, [october.id.to_s, september.id.to_s])
    c.define_singleton_method(:preload_jeevika_payment_passbooks!) { |_| nil }
    c.define_singleton_method(:preload_jeevika_bill_process_totals) { |_| nil }
    c.define_singleton_method(:jeevika_bill_vrp) { |_| nil }
    c.define_singleton_method(:jeevika_bill_bank_rows) { |_| [] }
    c.define_singleton_method(:jeevika_bill_summary) { |_| { activity_groups: nil, activity_names: nil } }
    c.define_singleton_method(:jeevika_jankar_bill_total_payment) { |_| 100 }

    capture { c.send(:jeevika_bill_payment_rows, [october, september], "October") }
    assert_equal [october.id.to_s], c.instance_variable_get(:@jeevika_payment_history_by_bill_id).keys
  end

  private

  def calculator(mapped)
    c = ModulesController.new
    c.request = ActionDispatch::TestRequest.create
    c.params = ActionController::Parameters.new
    c.define_singleton_method(:current_app_user) { { "user_type" => "admin", "record_type" => "User" } }
    c.define_singleton_method(:vrp_login_user?) { false }
    c.define_singleton_method(:module_mapped_vrp_scope_active?) { !mapped.nil? }
    c.define_singleton_method(:module_cluster_visible_vrp_ids) { mapped || [] }
    c
  end

  def owner(i)
    v = Vrp.new(name: "Billing JJ #{i}", user_name: "billing_jj_#{i}", aadhar_no: "123456789012", account_no: "123",
      address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "billing#{i}@example.test", experience_in_years: 0, father_husband_name: "Test", gender: 1,
      ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    v.save!(validate: false)
    v
  end

  def target(vrp, month, i)
    TargetMapping.create!(vrp: vrp, fco_id: "F", ics_id: "I", ics_name: i.even? ? "Z" : "A", village_id: "V",
      village_name: "Village #{i}", month_name: month, main_activity_name: "Training", activity_name: "Work", target_quantity: 1)
  end

  def totals(c, bill)
    [c.send(:jeevika_jankar_bill_total_target, bill), c.send(:jeevika_jankar_bill_total_achievement, bill)]
  end

  def capture
    queries = []
    subscriber = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && !payload[:cached] && payload[:sql].start_with?("SELECT")
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
