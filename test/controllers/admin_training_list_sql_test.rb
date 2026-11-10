require "test_helper"

class AdminTrainingListSqlTest < ActiveSupport::TestCase
  test "SQL admin page matches original pending date-second and ID sort with full attributes" do
    rows = 140.times.map do |index|
      ModuleRecord.create!(module_slug: "training-form", created_at: Time.utc(2026, 10, 1) + index / 3 + (index % 3) * 0.1,
        data: { "month" => "October", "trainer_name" => "Trainer #{index}",
          "photo_front_view" => ["x" * 10000], "selected_farmer_ids" => [index.to_s] })
    end
    rows.first(25).each do |row|
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
        data: { "record_id" => row.id, "status" => "Pending" })
    end
    ["Approved", "Rejected", nil, false, [], {}, "pending", " Pending "].each_with_index do |status, index|
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, created_at: 1.year.ago,
        data: { "record_id" => rows[index].id.to_s, "status" => status })
    end
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => "0#{rows.last.id}", "status" => "Pending" })
    revisions = ModuleRecordReadQuery.latest_training_revision_summaries.to_a.index_by { |r| r.data["record_id"].to_s }
    scope = ModuleRecord.where(module_slug: "training-form")
    expected = scope.to_a.min_by(100) do |row|
      [revisions[row.id.to_s]&.data&.[]("status") == "Pending" ? 0 : 1, -(row.created_at || Time.at(0)).to_i, -row.id]
    end
    controller = calculator
    instantiated = 0
    callback = ->(*args) { instantiated += args.last[:record_count] }
    actual = nil
    ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") { actual = controller.send(:module_records) }
    assert_equal expected.map(&:attributes), actual.map(&:attributes)
    selected_revision_count = expected.count { |row| revisions[row.id.to_s] }
    # Cached summary stand-ins do not emit instantiation notifications; only
    # the 100 complete training rows are queried/hydrated as model batches.
    assert_equal 100, instantiated
    assert_equal selected_revision_count, controller.instance_variable_get(:@training_edit_revisions_by_record).size
    expected.each do |row|
      revision = revisions[row.id.to_s]
      actual_revision = controller.send(:training_edit_revision_for, row, skip_auto_assign: true)
      if revision
        assert_equal revision.attributes, actual_revision.attributes
        assert_predicate actual_revision, :readonly?
      else
        assert_nil actual_revision
      end
    end
    assert_equal expected.map { |row| row.id.to_s }, controller.instance_variable_get(:@training_edit_revision_record_ids)
    assert_equal 140, calculator(all: "1").send(:module_records).size
  end

  test "admin page retains its revision snapshot after a subsequent decision" do
    row = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => row.id.to_s, "status" => "Pending", "approval_role" => "agronomist" })
    controller = calculator
    selected = controller.send(:module_records).sole
    revision.update!(data: revision.data.merge("status" => "Approved"))
    assert_equal "Pending", controller.send(:training_edit_revision_for, selected, skip_auto_assign: true).data["status"]
    fresh = calculator
    fresh.send(:module_records)
    assert_equal "Approved", fresh.send(:training_edit_revision_for, selected, skip_auto_assign: true).data["status"]
  end

  test "admin list respects a revision snapshot captured earlier in the request" do
    row = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => row.id.to_s, "status" => "Pending", "approval_role" => "agronomist" })
    controller = calculator
    assert_equal "Pending", controller.send(:training_edit_revision_for, row, skip_auto_assign: true).data["status"]
    revision.update!(data: revision.data.merge("status" => "Approved"))
    controller.send(:module_records)
    assert_equal "Pending", controller.send(:training_edit_revision_for, row, skip_auto_assign: true).data["status"]
  end

  test "non HTML admin reads retain all rows and original full data" do
    101.times { |i| ModuleRecord.create!(module_slug: "training-form", data: { "selected_farmer_ids" => [i.to_s] }) }
    %w[json xlsx].each do |format|
      controller = calculator
      controller.request.format = format
      result = controller.send(:module_records)
      assert_equal 101, result.size
      assert result.all? { |row| row.data.key?("selected_farmer_ids") }
    end
  end

  test "staff visibility is applied before the existing list limit" do
    rows = 105.times.map { |i| ModuleRecord.create!(module_slug: "training-form", data: { "trainer_name" => "Trainer #{i}" }) }
    allowed = rows.first(2).map(&:id)
    controller = calculator
    controller.instance_variable_set(:@current_app_user, { "user_type" => "User" })
    controller.define_singleton_method(:target_record_visible?) { |row| allowed.include?(row.id) }
    assert_equal allowed.reverse, controller.send(:module_records).map(&:id)
  end

  private

  def calculator(**params)
    ModulesController.new.tap do |controller|
      controller.request = ActionDispatch::TestRequest.create
      controller.params = ActionController::Parameters.new({ slug: "training-form-list" }.merge(params))
      controller.instance_variable_set(:@slug, "training-form-list")
      controller.instance_variable_set(:@current_app_user, { "user_type" => "admin" })
    end
  end
end
