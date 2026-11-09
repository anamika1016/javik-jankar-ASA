require "test_helper"

class LatestTrainingRevisionReadTest < ActiveSupport::TestCase
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
