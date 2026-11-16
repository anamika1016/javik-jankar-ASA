require "test_helper"

class BillDetailHistoryReadTest < ActiveSupport::TestCase
  test "eye detail scopes approval history before visibility without changing selected history" do
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Submitted" })
    selected = 2.times.map do |i|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: {
        "bill_id" => bill.id.to_s, "action" => i.zero? ? "Submitted" : "Approved", "remarks" => "Selected #{i}"
      })
    end
    30.times { |i| ModuleRecord.create!(module_slug: "jeevika-jankar-bill-approval-history", data: { "bill_id" => "other-#{i}", "action" => "Approved" }) }
    expected = ModulesController.new.send(:jeevika_bill_approval_history, bill).map(&:attributes)
    controller = ModulesController.new
    controller.params = ActionController::Parameters.new(view_id: bill.id)
    controller.define_singleton_method(:jeevika_jankar_bill_record_visible?) do |record|
      # Visibility may read approval history before the template does.
      send(:jeevika_bill_approval_history, record).last&.data&.[]("action") == "Approved"
    end
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] if args.last[:sql].match?(/SELECT.*FROM "module_records"/m) }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      controller.send(:prepare_jeevika_jankar_bill_list)
      assert_equal bill.id, controller.instance_variable_get(:@bill_detail_record).id
      assert_equal expected, controller.send(:jeevika_bill_approval_history, bill).map(&:attributes)
    end
    history_sql = queries.find { |sql| sql.include?("bill_id") }
    assert_includes history_sql, "IN"
    assert_equal selected.map(&:id), controller.send(:jeevika_bill_approval_history_by_bill_id).values.flatten.map(&:id)
  end

  test "print action scopes selected history before its unchanged download authorization" do
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: { "status" => "Final Approved" })
    controller = ModulesController.new
    controller.params = ActionController::Parameters.new(id: bill.id)
    controller.define_singleton_method(:load_module!) { nil }
    checked = nil
    controller.define_singleton_method(:jeevika_jankar_bill_downloadable?) do |record|
      checked = [record.id, @jeevika_bill_history_record_ids]
      true
    end
    controller.define_singleton_method(:render) { |*args, **options| [args, options] }
    controller.download_bill
    assert_equal [bill.id, [bill.id.to_s]], checked
    assert_equal [], controller.instance_variable_get(:@records)
    assert controller.instance_variable_get(:@bill_print_mode)
  end
end
