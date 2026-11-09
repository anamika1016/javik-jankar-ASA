require "test_helper"

class LatestTrainingRevisionReadTest < ActiveSupport::TestCase
  test "training edit reads only its own latest revision and retains complete summary output" do
    training = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    20.times do |index|
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
        data: { "record_id" => "other-#{index}", "status" => "Pending", "before" => { "photo" => "x" * 10000 } })
    end
    ["Approved", "Rejected", "Pending"].each do |status|
      latest = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, created_at: 1.year.ago,
        data: { "record_id" => training.id.to_s, "status" => status, "approval_role" => "agronomist",
          "legacy_metadata" => { "kept" => true }, "before" => { "photo" => "large" }, "proposed" => {} })
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
        data: { "record_id" => "0#{training.id}", "status" => "Pending" })
      controller = ModulesController.new
      controller.request = ActionDispatch::TestRequest.create
      controller.params = ActionController::Parameters.new(slug: "training-form", id: training.id.to_s)
      controller.define_singleton_method(:module_record_visible_for_current_context?) { |_| true }
      controller.define_singleton_method(:render) { |*| }
      instantiated = 0
      callback = ->(*args) { instantiated += args.last[:record_count] }
      ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") { controller.edit }
      actual = controller.instance_variable_get(:@training_edit_revision)
      assert_equal latest.id, actual.id
      assert_equal latest.data.except("before", "proposed", "evidence", "history"), actual.data
      assert_equal [training.id.to_s], controller.instance_variable_get(:@training_edit_revision_record_ids)
      assert_equal 2, instantiated, "only the selected training and latest revision should be loaded"
    end
  end

  test "repeated training row and button lookups build the candidate SQL only once" do
    records = 200.times.map { |index| ModuleRecord.new(id: index + 100000, module_slug: "training-form") }
    revision = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => records.first.id.to_s, "status" => "Pending" })
    controller = ModulesController.new
    controller.instance_variable_set(:@training_edit_revision_record_ids, records.map { |record| record.id.to_s })
    builds = 0
    trace = TracePoint.new(:call) do |event|
      builds += 1 if event.method_id == :latest_training_revision_summaries && event.self == ModuleRecordReadQuery
    end
    trace.enable do
      3.times do
        assert_equal revision.id, controller.send(:training_edit_revision_for, records.first, skip_auto_assign: true).id
        records.drop(1).each do |record|
          assert_nil controller.send(:training_edit_revision_for, record, skip_auto_assign: true)
        end
      end
    end
    assert_equal 1, builds
  end

  test "targeted latest reads preserve complete summary output and exact reference matching" do
    %w[12 012 missing-owner other].each do |reference|
      3.times do |index|
        ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, data: {
          "record_id" => reference, "status" => index == 2 ? "Approved" : "Pending",
          "legacy_metadata" => { "retained" => true }, "proposed" => { "large" => "x" * 10000 }
        })
      end
    end
    ModuleRecord.create!(module_slug: "unrelated", data: { "record_id" => "12", "status" => "Pending" })
    [["12"], ["012", "12", "12", "absent"], [nil, "missing-owner"], [nil]].each do |ids|
      baseline = ModuleRecord.where(module_slug: TrainingEditApproval::SLUG)
        .where("data::jsonb ->> 'record_id' IN (?)", ids)
        .select("DISTINCT ON ((data::jsonb ->> 'record_id')) id")
        .order(Arel.sql("(data::jsonb ->> 'record_id'), id DESC"))
      expected = TrainingEditApproval.summary_scope(ModuleRecord.where(id: baseline)).order(:id)
        .map { |record| [record.id, record.data] }
      actual = ModuleRecordReadQuery.latest_training_revision_summaries(record_ids: ids).order(:id)
        .map { |record| [record.id, record.data] }
      assert_equal expected, actual
    end
  end
end
