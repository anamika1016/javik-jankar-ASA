require "test_helper"

class GramOptionsProjectionTest < ActiveSupport::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end
  teardown { Rails.cache = @previous_cache }

  test "gram dropdown projection preserves legacy aliases types and first non-code precedence" do
    values = [nil, false, true, 123, " 12/34 ", " Name <& ", ["Array"], { "label" => "Object" }, " "]
    random = Random.new(71)
    60.times do |i|
      data = ModulesController::GRAM_PANCHAYAT_NAME_KEYS.index_with { values.sample(random: random) }
      data["status"] = i.even? ? "Active" : "Inactive"
      data["unrelated_upload"] = "x" * 10000
      ModuleRecord.create!(module_slug: "gram-panchayat-master", created_at: Time.at(i), data: data)
    end
    controller = ModulesController.new
    scope = controller.send(:active_module_records_scope, "gram-panchayat-master")
    expected = scope.order(created_at: :desc).filter_map { |row| controller.send(:gram_panchayat_name_from_record, row) }.uniq
    instantiated = 0
    callback = ->(*args) { instantiated += args.last[:record_count] }
    actual = nil
    ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") do
      actual = ModulesController.new.send(:values_from_module, "gram-panchayat-master", "gram_panchayat_name")
    end
    assert_equal expected, actual
    assert_equal 0, instantiated
    actual.clear
    assert_equal expected, ModulesController.new.send(:values_from_module, "gram-panchayat-master", "gram_panchayat_name")
    row = scope.first
    row.update_columns(data: { "gram_panchayat_name" => "Updated Gram", "status" => "Active" })
    assert_includes ModulesController.new.send(:values_from_module, "gram-panchayat-master", "gram_panchayat_name"), "Updated Gram"
  end
end
