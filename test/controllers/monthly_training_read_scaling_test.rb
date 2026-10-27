require "test_helper"

class MonthlyTrainingReadScalingTest < ActiveSupport::TestCase
  test "SQL revision filtering matches latest ID precedence and all revision statuses" do
    states = [nil, "Approved", "approved", "Pending", "Rejected", "", false, 5, [], {}]
    records = states.each_with_index.map do |status, index|
      row = ModuleRecord.create!(module_slug: "training-form", created_at: index.minutes.ago,
        data: { "month" => " October ", "photo_front_view" => ["x" * 10000] })
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => row.id.to_s, "status" => "Approved" })
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, created_at: 1.year.ago,
        data: { "record_id" => row.id.to_s, "status" => status, "deleted" => true })
      row
    end
    untouched = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "approval_status" => "Pending" })
    ModuleRecord.create!(module_slug: "unrelated", data: { "record_id" => untouched.id.to_s, "status" => "Rejected" })
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "September" })
    assert_original_parity("October")
    assert_original_parity("")
    result = ModulesController.new.send(:dashboard_training_form_records_by_month, "october")
    assert_includes result.map(&:id), untouched.id
    assert_includes result.map(&:id), records[1].id
    refute_includes result.map(&:id), records[0].id
    assert_equal records[1].data, result.find { |row| row.id == records[1].id }.data
  end

  test "status filtering retains Ruby normalization and JSON value types" do
    [nil, "Active", " Pending ", " ReJeCtEd ", "Returned", "\tINACTIVE\n", false, 0,
      ["Rejected"], { "label" => "return" }, "Not Rejected", "approved"].each do |status|
      ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "approval_status" => status })
    end
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "deleted" => true })
    ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "status" => "Inactive" })
    assert_original_parity("October")
  end

  test "blocked photo payloads are not instantiated and repeat reads add no queries" do
    20.times do |index|
      row = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October", "photo_front_view" => ["large" * 10000] })
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => row.id.to_s, "status" => "Pending" }) if index < 18
    end
    controller = ModulesController.new
    instantiated = 0
    queries = []
    object_subscriber = ->(*args) { instantiated += args.last[:record_count] }
    sql_subscriber = ->(*args) { queries << args.last[:sql] if args.last[:name] != "SCHEMA" && args.last[:sql].start_with?("SELECT") }
    ActiveSupport::Notifications.subscribed(object_subscriber, "instantiation.active_record") do
      ActiveSupport::Notifications.subscribed(sql_subscriber, "sql.active_record") do
        result = controller.send(:dashboard_training_form_records_by_month, "october")
        assert_equal 2, result.size
        assert_same result, controller.send(:dashboard_training_form_records_by_month, "october")
      end
    end
    assert_equal 2, instantiated
    assert_equal 2, queries.size
    assert_includes queries.first, "DISTINCT ON"
    assert controller.instance_variable_defined?(:@unapproved_training_record_ids)
  end

  test "monthly read preserves a revision snapshot already captured in the request" do
    blocked = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    allowed = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => blocked.id.to_s, "status" => "Pending" })
    controller = ModulesController.new
    refute controller.send(:training_record_countable?, blocked)
    assert controller.send(:training_record_countable?, allowed)
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => blocked.id.to_s, "status" => "Approved" })
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => allowed.id.to_s, "status" => "Pending" })
    assert_equal [allowed.id], controller.send(:dashboard_training_form_records_by_month, "october").map(&:id)
  end

  test "first monthly read captures the snapshot reused by a later month" do
    october = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    september = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "September" })
    controller = ModulesController.new
    assert_equal [october.id], controller.send(:dashboard_training_form_records_by_month, "october").map(&:id)
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: { "record_id" => september.id.to_s, "status" => "Pending" })
    assert_equal [september.id], controller.send(:dashboard_training_form_records_by_month, "september").map(&:id)
  end

  test "legacy reference IDs retain exact string matching without numeric coercion" do
    row = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    scope = ModuleRecord.where(id: row.id)
    misleading = Set.new(["0#{row.id}", " #{row.id} ", "missing", nil, row.id])
    assert_equal [row.id], ModuleRecordReadQuery.without_unapproved_training_records(scope, misleading).pluck(:id)
    misleading << row.id.to_s
    assert_empty ModuleRecordReadQuery.without_unapproved_training_records(scope, misleading).pluck(:id)
  end

  private

  def assert_original_parity(month)
    normalized = month.strip.downcase
    old_revision_ids = ModuleRecord.where(module_slug: TrainingEditApproval::SLUG)
      .select("DISTINCT ON ((data::jsonb ->> 'record_id')) (data::jsonb ->> 'record_id') AS approval_record_id, (data::jsonb ->> 'status') AS approval_status")
      .order(Arel.sql("(data::jsonb ->> 'record_id'), id DESC")).filter_map do |revision|
        id = revision.attributes["approval_record_id"].to_s
        id if id.present? && revision.attributes["approval_status"] != "Approved"
      end
    assert_equal old_revision_ids, TrainingEditApproval.unapproved_record_ids
    original = ModulesController.new
    scope = original.send(:active_module_records_scope, "training-form").order(created_at: :desc)
    scope = scope.where("LOWER(BTRIM(data::jsonb ->> 'month')) = ?", normalized) if normalized.present?
    expected = scope.to_a.select { |record| original.send(:training_record_countable?, record) }
    actual = ModulesController.new.send(:dashboard_training_form_records_by_month, normalized)
    assert_equal expected.map(&:attributes), actual.map(&:attributes)
  end
end
