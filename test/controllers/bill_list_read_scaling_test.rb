require "test_helper"

class BillListReadScalingTest < ActiveSupport::TestCase
  test "bill projection preserves summaries types and item order and keeps detail payload intact" do
    payloads = [
      { "bill_items" => [{ "activity" => "A", "assigned_count" => 4, "farmer_details" => [{ "name" => "x" * 100_000 }] },
        { "activity" => "B", "achievement_count" => "2", "farmer_details" => [] }], "observations" => { "work" => "good" } },
      { "bill_items" => { "one" => { "farmer_details" => [1], "assigned_count" => 2 } } },
      { "bill_items" => [] }, { "bill_items" => [nil, false, 5, "legacy", []] }
    ]
    controller = ModulesController.new
    payloads.each do |data|
      record = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: data)
      projected = controller.send(:bill_summary_scope, ModuleRecord.where(id: record.id)).first
      expected = data.deep_dup
      if expected["bill_items"].is_a?(Array)
        expected["bill_items"].each { |item| item.delete("farmer_details") if item.is_a?(Hash) }
      end
      assert_equal expected, projected.data
      assert_equal data, record.reload.data
    end
  end

  test "approved payment scope matches the existing status predicate" do
    controller = ModulesController.new
    statuses = ["Final Approved", "prefix FINAL APPROVED suffix", "Pending", "Rejected", nil, 5]
    bills = statuses.map do |status|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => status })
    end

    expected_ids = bills.select { |bill| controller.send(:jeevika_bill_final_approved?, bill) }.map(&:id).sort
    actual_ids = controller.send(:jeevika_bill_final_approved_scope,
      ModuleRecord.where(id: bills.map(&:id))).pluck(:id).sort

    assert_equal expected_ids, actual_ids
  end

  test "batched bill totals equal individual totals including numeric month fallback" do
    bills = 5.times.map do |index|
      vrp = Vrp.new(name: "Scaling JJ #{index}", aadhar_no: "123456789012", account_no: "123",
        address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
        email: "scaling-#{index}@example.test", experience_in_years: 0, father_husband_name: "Test",
        gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
      vrp.save!(validate: false)
      farmers = 2.times.map { |number| Afl.create!(farmer_name: "Scaling Farmer #{index}-#{number}", fco_id: "scaling", fco: "Scaling") }
      target = TargetMapping.create!(vrp: vrp, fco_id: "scaling", fco_name: "Scaling", ics_id: "ics", village_id: "village",
        month_name: index == 4 ? "9" : "September", main_activity_name: "Farmers' Training",
        activity_name: "Soil", target_quantity: 2, afl_ids: farmers.map(&:id))
      if index.even?
        ModuleRecord.create!(module_slug: "training-form", data: {
          "jeevika_jankar_id" => vrp.id.to_s, "month" => target.month_name,
          "main_activity" => "Farmers' Training", "main_activity_type" => "Training", "sub_activity" => "Soil",
          "target_mapping_id" => target.id.to_s, "selected_farmer_ids" => [farmers.first.id.to_s],
          "training_method" => "OPG Training", "training_date" => "2026-09-03"
        })
      end
      ModuleRecord.new(data: { "select_vrp" => vrp.id.to_s, "bill_month" => "September", "total_target" => "99" })
    end
    old = calculator
    before_queries, expected = read_queries do
      bills.map { |bill| [old.send(:jeevika_jankar_bill_total_target, bill), old.send(:jeevika_jankar_bill_total_achievement, bill)] }
    end
    optimized = calculator
    previous_summary = { saved: true }
    optimized.instance_variable_set(:@jeevika_jankar_target_summary, previous_summary)
    after_queries, actual = read_queries do
      optimized.send(:preload_jeevika_bill_process_totals, bills)
      bills.map { |bill| [optimized.send(:jeevika_jankar_bill_total_target, bill), optimized.send(:jeevika_jankar_bill_total_achievement, bill)] }
    end
    assert_equal expected, actual
    assert expected.first(4).any? { |_target, achievement| achievement.to_f.positive? }, "Parity must cover real training achievements"
    assert_equal previous_summary, optimized.instance_variable_get(:@jeevika_jankar_target_summary)
    assert_operator after_queries, :<, before_queries
  end

  test "mapped and JJ logins retain the individual totals path" do
    controller = calculator
    controller.define_singleton_method(:module_mapped_vrp_scope_active?) { true }
    controller.define_singleton_method(:jeevika_jankar_bill_rows) { |**_| raise "Scope fallback must stay individual" }
    controller.send(:preload_jeevika_bill_process_totals, [ModuleRecord.new(data: { "select_vrp" => "1", "bill_month" => "September" })])
    assert_nil controller.instance_variable_get(:@jeevika_bill_process_totals)
  end

  test "payment rows contain the same displayed bill values without building full bill-list actions" do
    controller = calculator
    record = ModuleRecord.new(id: 42, module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => "12", "select_vrp_name" => "JJ Twelve", "financial_year" => "2026-27",
      "bill_month" => "October", "grand_total" => "5000.00"
    })
    vrp = Struct.new(:bank_passbook_upload).new(:passbook)
    controller.define_singleton_method(:jeevika_bill_final_approved?) { |_| true }
    controller.define_singleton_method(:preload_jeevika_payment_passbooks!) { |_| nil }
    controller.define_singleton_method(:preload_jeevika_bill_process_totals) { |_| nil }
    controller.define_singleton_method(:jeevika_bill_vrp) { |_| vrp }
    controller.define_singleton_method(:jeevika_bill_bank_rows) { |_| [{ bank_name: "Bank", ifsc_code: "IFSC", account_number: "123" }] }
    controller.define_singleton_method(:jeevika_bill_status_label) { |_| "Final Approved" }
    controller.define_singleton_method(:jeevika_bill_summary) do |_|
      { activity_groups: "Training", activity_names: "Soil", total_amount: 5000 }
    end
    controller.define_singleton_method(:jeevika_jankar_display_name) { |value| value }
    controller.define_singleton_method(:jeevika_jankar_vrp_label) { |_| "JJ Twelve" }
    controller.define_singleton_method(:jeevika_jankar_bill_total_payment) { |_| "5000.00" }
    controller.define_singleton_method(:jeevika_jankar_bill_total_target) { |_| 4 }
    controller.define_singleton_method(:jeevika_jankar_bill_total_achievement) { |_| 3 }
    controller.define_singleton_method(:download_bill_module_record_path) { |slug, row| "/#{slug}/#{row.id}/download" }
    controller.define_singleton_method(:jeevika_bill_rows) { |_| raise "Payment list must not build full bill-list rows" }

    rows = controller.send(:jeevika_bill_payment_rows, [record], "October")

    assert_equal [{
      id: 42,
      download_path: "/jeevika-jankar-bill-list/42/download",
      status: "Final Approved",
      status_class: "approved",
      vrp_id: "12",
      name: "JJ Twelve",
      financial_year: "2026-27",
      bill_month: "October",
      activity_groups: "Training",
      amount: "5000.00",
      activity_names: "Soil",
      target: 4,
      achievement: 3,
      bank_name: "Bank",
      ifsc_code: "IFSC",
      account_number: "123",
      passbook_attachment: :passbook
    }], rows
  end

  test "bill identity preload only caches JJs referenced by the current bill rows" do
    matching = build_bill_lookup_vrp("Bill Lookup JJ", "bill_lookup_jj")
    unrelated = build_bill_lookup_vrp("Unrelated JJ", "unrelated_jj")
    matching.update_columns(agreement_signature_data: "signature payload" * 100)
    record = ModuleRecord.new(module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => matching.id.to_s,
      "select_vrp_name" => "BILL LOOKUP JJ",
      "bill_items" => [{ "vrp_name" => matching.user_name }]
    })

    controller = calculator
    controller.send(:preload_bill_list_identities!, [record])
    cached = controller.instance_variable_get(:@cached_vrps_by_id)

    assert_equal [matching.id.to_s], cached.keys
    assert_equal matching.id, controller.send(:cached_vrp_lookup, "bill lookup jj").id
    assert_nil controller.send(:cached_vrp_lookup, unrelated.id)
    assert_not cached.fetch(matching.id.to_s).has_attribute?(:agreement_signature_data)
  end

  test "bill creator identity preload batches ID username and email into one query" do
    user = User.create!(user_name: "bill_creator_batch", password: "secret", first_name: "Bill", last_name: "Creator", email: "bill-creator@example.test")
    record = ModuleRecord.new(module_slug: "jeevika-jankar-bill-process", data: {
      "created_by_id" => user.id.to_s,
      "created_by_username" => user.user_name,
      "created_by_email" => user.email
    })
    controller = calculator
    user_queries, = read_queries do
      controller.send(:preload_bill_list_identities!, [record])
    end

    assert_equal user, controller.send(:cached_user_find_by, id: user.id.to_s)
    assert_equal user, controller.send(:cached_user_find_by, user_name: user.user_name)
    assert_equal user, controller.send(:cached_user_find_by, email: user.email)
    assert_equal 1, user_queries
  end

  test "bill process duplicate keys preserve rejection flags without loading bill evidence" do
    controller = calculator
    ["Active", "Rejected", "Returned", "Submitted"].each_with_index do |status, index|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
        "select_vrp" => "#{index + 1}", "bill_month" => "September", "status" => status,
        "deleted" => index == 3, "bill_items" => [{ "farmer_details" => [{ "name" => "x" * 100_000 }] }]
      })
    end
    expected = ModuleRecord.where(module_slug: "jeevika-jankar-bill-process").order(created_at: :desc)
      .select { |bill| controller.send(:jeevika_jankar_bill_blocks_duplicate?, bill) }
      .map { |bill| { id: bill.id.to_s, vrp_id: bill.data["select_vrp"].to_s, month: bill.data["bill_month"].to_s } }
      .reject { |row| row[:vrp_id].blank? || row[:month].blank? }
    checked = []
    original_check = controller.method(:jeevika_jankar_bill_blocks_duplicate?)
    controller.define_singleton_method(:jeevika_jankar_bill_blocks_duplicate?) do |bill|
      checked << bill.data
      original_check.call(bill)
    end
    assert_equal expected, controller.send(:jeevika_jankar_existing_bill_keys)
    assert checked.all? { |data| !data.key?("bill_items") }, "Duplicate checks must not load unused evidence"
  end

  private

  def calculator
    controller = ModulesController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new
    controller.define_singleton_method(:current_app_user) { { "user_type" => "admin", "record_type" => "User" } }
    controller
  end

  def read_queries
    queries = 0
    callback = ->(*args) do
      payload = args.last
      queries += 1 if payload[:name] != "SCHEMA" && !payload[:cached] && payload[:sql].start_with?("SELECT")
    end
    result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    [queries, result]
  end

  def build_bill_lookup_vrp(name, user_name)
    vrp = Vrp.new(name: name, user_name: user_name, aadhar_no: "123456789012", account_no: "123",
      address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "#{user_name}@example.test", experience_in_years: 0, father_husband_name: "Test",
      gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    vrp
  end
end
