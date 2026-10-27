require "test_helper"

class ModuleScalingTest < ActiveSupport::TestCase
  test "LG selections use one query and preserve order and slug ownership" do
    state = ModuleRecord.create!(module_slug: "state-master", data: { "state" => "S" })
    village = ModuleRecord.create!(module_slug: "village-master", data: { "village" => "V" })
    controller = ModulesController.new
    controller.params = ActionController::Parameters.new(row_tokens: [
      "village-master:#{village.id}", "state-master:#{state.id}",
      "state-master:#{state.id}", "state-master:#{village.id}", "new-user:#{state.id}"
    ])
    queries = capture_module_queries do
      assert_equal [village.id, state.id], controller.send(:lg_directory_selected_records).map(&:id)
    end
    assert_equal 1, queries.size
  end

  test "training list hydrates only visible page and keeps pending first" do
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, "training-form-list")
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new
    controller.define_singleton_method(:preload_target_visibility_vrps!) { |_| }
    controller.define_singleton_method(:target_record_visible?) { |record| record.data["trainer_name"] != "Hidden" }
    controller.define_singleton_method(:preload_training_record_trainer_identities!) { |_| }
    oldest = nil
    105.times do |index|
      record = ModuleRecord.create!(module_slug: "training-form", created_at: index.minutes.ago,
        data: { "trainer_name" => "Visible", "farmer_ids" => ["farmer-#{index}"],
          "photo_front_view" => ["image-#{index}"] })
      oldest = record
    end
    ModuleRecord.create!(module_slug: "training-form", data: { "trainer_name" => "Hidden" })
    ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => oldest.id.to_s, "status" => "Pending" })
    records = nil
    queries = capture_module_queries { records = controller.send(:module_records) }
    assert_equal 100, records.size
    assert_equal oldest.id, records.first.id
    assert records.all? { |record| record.data["trainer_name"] == "Visible" }
    assert_equal oldest.data["farmer_ids"], records.first.data["farmer_ids"]
    assert_equal oldest.data["photo_front_view"], records.first.data["photo_front_view"]
    assert_equal 3, queries.size
    assert_includes queries.first, "data::jsonb - ARRAY"
    assert_match(/WHERE.*"id" IN/m, queries.last)
    controller.params = ActionController::Parameters.new(all: "1")
    full_order = controller.send(:module_records)
    assert_equal full_order.first(100).map(&:attributes), records.map(&:attributes)
  end

  test "removed reports and farm feature have no routes or navigation" do
    %w[farmer-participation-report weekly-activity-target-report farmer-training-target-status].each do |slug|
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/dashboard/#{slug}", method: :get)
      end
    end
    links = ApplicationHelper::SIDEBAR_SECTIONS.flat_map { |section| section[:links] }
    refute links.any? { |link| link.first == "Farmer Participation Report" }
    refute ApplicationHelper::SIDEBAR_SECTIONS.any? { |section| section[:title] == "Farmer Farm Information" }
    refute Rails.application.routes.routes.any? { |route| route.path.spec.to_s.include?("farmer-farm-information") }
  end

  test "latest revision summaries preserve latest ID precedence and skip historical payloads" do
    first = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "October" })
    second = ModuleRecord.create!(module_slug: "training-form", data: { "month" => "September" })
    5.times do
      ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
        data: { "record_id" => first.id.to_s, "status" => "Pending", "before" => { "large" => "x" * 10000 } })
    end
    latest = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG, created_at: 1.year.ago,
      data: { "record_id" => first.id.to_s, "status" => "Approved", "before" => { "large" => "x" * 10000 } })
    other = ModuleRecord.create!(module_slug: TrainingEditApproval::SLUG,
      data: { "record_id" => second.id.to_s, "status" => "Pending" })
    ModuleRecord.create!(module_slug: "unrelated", data: { "record_id" => first.id.to_s, "status" => "Pending" })
    instantiated = 0
    subscriber = ->(*args) { instantiated += args.last[:record_count] }
    summaries = nil
    queries = nil
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      queries = capture_module_queries do
        summaries = ModuleRecordReadQuery.latest_training_revision_summaries.order(id: :desc).to_a
      end
    end
    assert_equal [other.id, latest.id], summaries.map(&:id)
    assert_equal 2, instantiated
    assert_equal 1, queries.size
    refute summaries.any? { |row| row.data.key?("before") }
    assert_equal [latest.id], ModuleRecordReadQuery.latest_training_revision_summaries(record_ids: [first.id.to_s]).map(&:id)
  end

  test "training all and export retain full payloads without page cap" do
    records = 105.times.map do |index|
      ModuleRecord.create!(module_slug: "training-form", created_at: index.minutes.ago,
        data: { "trainer_name" => "Visible", "farmer_ids" => [index.to_s], "photo_front_view" => ["image-#{index}"] })
    end
    [{ all: "1" }, { format: "csv" }].each do |parameters|
      controller = ModulesController.new
      controller.instance_variable_set(:@slug, "training-form-list")
      controller.request = ActionDispatch::TestRequest.create
      controller.request.set_header("action_dispatch.request.formats", [Mime[:csv]]) if parameters[:format]
      controller.params = ActionController::Parameters.new(parameters)
      controller.define_singleton_method(:preload_target_visibility_vrps!) { |_| }
      controller.define_singleton_method(:target_record_visible?) { |_| true }
      controller.define_singleton_method(:preload_training_record_trainer_identities!) { |_| }
      result = controller.send(:module_records)
      assert_equal records.map(&:id), result.map(&:id)
      assert_equal records.map(&:data), result.map(&:data)
    end
  end

  test "training progress projection retains every calculation field without attachment payloads" do
    data = {
      "month" => "October", "training_date" => "2026-10-01", "selected_farmer_ids" => ["10"],
      "target_mapping_id" => "22", "ics" => "ICS", "village" => "Village", "training_location" => "Hall", "training_method" => "FFS",
      "main_activity" => "Training", "sub_activity" => "Topic", "trainer_name" => "JJ",
      "status" => "Active", "field_photo" => ["x" * 100_000], "attachment_upload" => ["y" * 100_000]
    }
    record = ModuleRecord.create!(module_slug: "training-form", data: data)

    projected = ModuleRecordReadQuery.training_progress_records(ModuleRecord.where(id: record.id)).first
    assert_equal data.except("field_photo", "attachment_upload"), projected.data
    assert_equal ["10"], projected.data["selected_farmer_ids"]
    refute projected.data.key?("field_photo")
    refute projected.data.key?("attachment_upload")
  end

  test "large master lists keep their order and searchable result set with server pagination" do
    records = 16.times.map do |index|
      ModuleRecord.create!(module_slug: "village-master", data: { "village" => format("Village %02d", index) })
    end
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, "village-master")
    controller.instance_variable_set(:@module, { fields: ["Village"] })
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new(page: "2")

    page_two = controller.send(:module_records)
    assert_equal [records.last.id], page_two.map(&:id)
    assert_equal 16, controller.instance_variable_get(:@module_records_total_count)
    assert_equal 2, controller.instance_variable_get(:@module_records_page_count)
    assert_equal 2, controller.instance_variable_get(:@module_records_page)

    controller.params = ActionController::Parameters.new(q: "Village 07")
    matching_page = controller.send(:module_records)
    assert_equal [records[7].id], matching_page.map(&:id)
    assert_equal 1, controller.instance_variable_get(:@module_records_total_count)

    controller.params = ActionController::Parameters.new(q: "Deactivate")
    assert_equal records.first(15).map(&:id), controller.send(:module_records).map(&:id)
    assert_equal 16, controller.instance_variable_get(:@module_records_total_count)
  end

  test "farmer profiles use AFL without removed farm tables" do
    farmer = Afl.create!(farmer_name: " AFL Farmer ", father_name: " Parent ", tracenet_no: "T1", village_name: "Village")
    controller = ModulesController.new
    profiles = controller.send(:dashboard_farmer_profiles_by_id, [farmer.id, "missing"])
    assert_equal "AFL Farmer", profiles[farmer.id.to_s][:farmer_name]
    assert_equal "Parent", profiles[farmer.id.to_s][:father_name]
    assert_equal "Farmer #missing", profiles["missing"][:farmer_name]
    assert_same profiles, controller.send(:dashboard_farmer_profiles_by_id, ["missing", farmer.id])
    refute ActiveRecord::Base.connection.table_exists?(:farmer_farm_information)
  end

  private

  def capture_module_queries
    queries = []
    subscriber = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"module_records"')
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
