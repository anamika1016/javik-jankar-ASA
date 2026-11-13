require "test_helper"

class TrainingOwnerCandidateIndexTest < ActiveSupport::TestCase
  test "owner candidates preserve all legacy aliases blank fallback duplicates and source order" do
    controller = ModulesController.new
    owner = Vrp.new(id: 12, name: "Test JJ", user_name: "jj_login", mobile_no: "9876543210")
    target = TargetMapping.new(month_name: "November")
    target.vrp = owner
    keys = %w[jeevika_jankar_id vrp_id select_vrp vrp_name jeevika_jankar_name trainer_contact trainer_name]
    values = ["12", "TEST JJ", " jj_login ", "9876543210", "Test JJ - 9876543210", "unrelated", nil, ""]
    records = keys.flat_map { |key| values.map { |value| ModuleRecord.new(data: { key => value }) } }
    records += [records.first, ModuleRecord.new(data: { "vrp_id" => "999", "trainer_name" => "Test JJ" })]
    controller.define_singleton_method(:dashboard_training_form_records_for_month) { |_| records }
    normalize = ->(value) { controller.send(:normalize_dashboard_text, value) }
    owner_values = [owner.id, owner.name, owner.user_name, owner.mobile_no,
      [owner.name, owner.mobile_no.presence].compact_blank.join(" - ")].map(&normalize).reject(&:blank?)
    expected = records.select do |record|
      record_values = keys.map { |key| normalize.call(record.data[key]) }.reject(&:blank?)
      record_values.empty? || (record_values & owner_values).any?
    end
    assert_equal expected.map(&:object_id), controller.send(:dashboard_training_candidates_for_target, target).map(&:object_id)
    assert_equal expected.map(&:object_id), controller.send(:dashboard_training_candidates_for_target, target).map(&:object_id)
    target.vrp = nil
    assert_same records, controller.send(:dashboard_training_candidates_for_target, target)
  end

  test "many owners scan source metadata once and retain only their matching candidates" do
    controller = ModulesController.new
    records = 200.times.map { |id| ModuleRecord.new(data: { "jeevika_jankar_id" => id.to_s }) }
    controller.define_singleton_method(:dashboard_training_form_records_for_month) { |_| records }
    reads = 0
    original = controller.method(:training_record_owner_values)
    controller.define_singleton_method(:training_record_owner_values) { |record| reads += 1; original.call(record) }
    150.times do |id|
      target = TargetMapping.new(month_name: "November")
      target.vrp = Vrp.new(id: id, name: "Owner #{id}")
      assert_equal [records[id]], controller.send(:dashboard_training_candidates_for_target, target)
    end
    assert_equal 200, reads, "Do not repeat the 200-row owner scan for each target"
  end

  test "dashboard without a farmer roll retains blank owner fallback and memoizes completed selection" do
    controller = ModulesController.new
    owner = Vrp.new(id: 12, name: "Dashboard JJ")
    target = TargetMapping.new(month_name: "November", vrp_id: owner.id)
    target.vrp = owner
    records = [ModuleRecord.new(id: 1, data: { "vrp_id" => "12" }),
      ModuleRecord.new(id: 2, data: {}), ModuleRecord.new(id: 3, data: { "vrp_id" => "999" })]
    reads = 0
    controller.define_singleton_method(:dashboard_training_form_records_for_month) do |*args, **options|
      reads += 1
      records
    end
    actual = controller.send(:dashboard_training_form_records, [target], [])
    assert_equal records.first(2), actual
    assert_same actual, controller.send(:dashboard_training_form_records, [target], [])
    assert_equal 1, reads
  end
  test "reused candidates isolate array edits and follow changed identities and source snapshots" do
    c = ModulesController.new
    owner = Vrp.new(id: 12, name: "First JJ", user_name: "login", mobile_no: "111")
    target = TargetMapping.new(month_name: "November", vrp: owner)
    records = [ModuleRecord.new(id: 1, data: { "trainer_name" => "First JJ" }),
      ModuleRecord.new(id: 2, data: { "trainer_name" => "Second JJ" }),
      ModuleRecord.new(id: 3, data: {}),
      ModuleRecord.new(id: 4, data: { "trainer_contact" => "222" })]
    records.insert(1, records.first)
    c.define_singleton_method(:dashboard_training_form_records_for_month) { |_| records }
    verify = lambda do
      expected = records.select { |r| c.send(:training_record_vrp_scope_matches?, r, owner) }
      actual = c.send(:dashboard_training_candidates_for_target, target)
      assert_equal expected.map(&:object_id), actual.map(&:object_id)
      actual.clear
      assert_equal expected.map(&:object_id), c.send(:dashboard_training_candidates_for_target, target).map(&:object_id)
    end
    verify.call
    owner.name = "Second JJ"
    verify.call
    owner.mobile_no = "222"
    verify.call
    owner.name = "First JJ"
    owner.mobile_no = "111"
    verify.call
    records = records.reverse + [ModuleRecord.new(id: 5, data: { "vrp_id" => "12" })]
    verify.call
  end

end
