require "test_helper"

class VrpFormLookupPerformanceTest < ActiveSupport::TestCase
  test "form option readers share records without changing labels or active filtering" do
    record = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Read State", "status" => "Active" })
    spaced_active = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Spaced Active", "status" => " Active " })
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Hidden State", "status" => "Inactive" })
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Deleted State", "deleted" => " YES " })
    controller = VrpsController.new
    queries = []
    callback = ->(*args) { queries << args.last[:sql] if args.last[:sql].match?(/SELECT.*FROM "module_records"/m) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal [["Read State", record.id], ["Spaced Active", spaced_active.id]], controller.send(:module_record_options, "state-master", "state_name")
      assert_equal ["Spaced Active", "Read State"], controller.send(:text_module_record_options, "state-master", "state_name")
      assert_equal [spaced_active.id, record.id], controller.send(:active_records_for_location, "state-master").map(&:id)
    end
    assert_equal 1, queries.size
  end

  test "VRP location hierarchy loads all active master modules in one query" do
    ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Batch State", "unused_large_payload" => "x" * 10_000 })
    ModuleRecord.create!(module_slug: "district-master", data: { "state_name" => "Batch State", "district_name" => "Batch District" })
    ModuleRecord.create!(module_slug: "village-master", data: {
      "state_name" => "Batch State", "district_name" => "Batch District", "block_name" => "Batch Block",
      "village_name" => "Batch Village", "status" => " Active "
    })
    ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Hidden Village", "status" => "Inactive" })
    controller = VrpsController.new
    queries = []
    callback = ->(*args) do
      sql = args.last[:sql]
      queries << sql if sql.match?(/SELECT.*FROM "module_records"/m)
    end

    mappings = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      mappings = controller.send(:location_hierarchy_mappings)
      assert_equal 6, VrpsController::LOCATION_HIERARCHY_MODULE_SLUGS.size
      assert mappings.any? { |row| row[:village] == "Batch Village" }
      assert_not mappings.any? { |row| row[:village] == "Hidden Village" }
      VrpsController::LOCATION_HIERARCHY_MODULE_SLUGS.each do |slug|
        controller.send(:active_records_for_location, slug)
      end
    end

    assert_equal 1, queries.size
    assert_includes queries.first, "module_slug"
    assert_includes queries.first, "jsonb_each"
    assert_not_includes queries.first, "unused_large_payload"
  end

  test "form master synchronization batches reads and keeps inactive flags current" do
    bank_name = "Sync Bank #{SecureRandom.hex(4)}"
    type_name = "Sync Type #{SecureRandom.hex(4)}"
    ModuleRecord.create!(module_slug: "bank-master", data: { "bank_name" => bank_name, "status" => "Active" })
    ModuleRecord.create!(module_slug: "bank-master", data: { "bank_name" => "  ", "status" => "Active" })
    ModuleRecord.create!(module_slug: "position-type", data: { "position_type_name" => type_name, "status" => "Inactive" })
    controller = VrpsController.new

    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:sql].match?(/FROM "(?:module_records|vrp_bank_masters|vrp_types)"/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      controller.send(:sync_existing_vrp_master_records)
    end

    assert_equal true, VrpBankMaster.find_by!(name: bank_name).is_active
    assert_equal false, VrpType.find_by!(type_name: type_name).is_active
    assert_operator queries.count { |sql| sql.include?('"module_records"') }, :<=, 1
    assert_operator queries.count { |sql| sql.include?('"vrp_bank_masters"') }, :<=, 1
    assert_operator queries.count { |sql| sql.include?('"vrp_types"') }, :<=, 1
  end

  test "VRP edit data is preloaded with its profile, bank and attachment metadata" do
    controller = VrpsController.new
    vrp = Vrp.new
    controller.request = ActionDispatch::TestRequest.create
    controller.params = ActionController::Parameters.new(id: "1")
    controller.define_singleton_method(:find_manageable_vrp) { |_| vrp }
    controller.define_singleton_method(:set_form_dependencies) { nil }
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:sql].match?(/FROM "(?:vrps|vrp_profiles|vrp_bank_masters|active_storage_attachments|active_storage_blobs)"/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      controller.send(:set_edit_dependencies)
      vrp = controller.instance_variable_get(:@vrp)
      vrp.vrp_profile
      vrp.vrp_bank_master
      vrp.bank_passbook_upload.attachment&.blob
    end

    assert_operator queries.size, :<=, 6
  end

  test "cluster scoped VRP list filters fuzzy labels before loading matching rows" do
    cluster_label = "Lookup#{SecureRandom.hex(4)} Person"
    matching = create_test_vrp("Cluster Match", cluster_incharge: "#{cluster_label} (Cluster Incharge)")
    create_test_vrp("Cluster Other", cluster_incharge: "Other#{SecureRandom.hex(4)} Person (Cluster Incharge)")
    controller = VrpsController.new
    controller.define_singleton_method(:current_cluster_incharge_labels) { [cluster_label] }

    queries = []
    callback = ->(*args) { queries << args.last[:sql] if args.last[:sql].include?(%Q{FROM "vrps"}) }
    visible = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      visible = controller.send(:cluster_mapped_vrps)
    end

    assert_equal [matching.id], visible.map(&:id)
    assert_equal 2, queries.size
    assert_match(/DISTINCT.*cluster_incharge/m, queries.first)
    assert_match(/WHERE.*cluster_incharge/m, queries.last)
  end

  test "office scoped VRP list preserves normalized FCO matching" do
    office = "Performance#{SecureRandom.hex(4)}"
    matching = create_test_vrp("Office Match", fcoc: "FCO-C #{office}")
    create_test_vrp("Other Office", fcoc: "Elsewhere#{SecureRandom.hex(4)}")
    controller = VrpsController.new
    controller.define_singleton_method(:current_app_user) { { "office_name" => office } }

    queries = []
    callback = ->(*args) { queries << args.last[:sql] if args.last[:sql].include?(%Q{FROM "vrps"}) }
    visible = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      visible = controller.send(:office_scoped_vrps)
    end

    assert_equal [matching.id], visible.map(&:id)
    assert_equal 2, queries.size
    assert_match(/DISTINCT.*fcoc/m, queries.first)
    assert_match(/WHERE.*fcoc/m, queries.last)
  end

  test "approval candidates retain status and history rows with a narrow VRP projection" do
    status_candidate = create_test_vrp("Status Candidate", status: 25)
    history_candidate = create_test_vrp("History Candidate", status: 20)
    ModuleRecord.create!(module_slug: "vrp-approval-history", data: { "vrp_id" => history_candidate.id.to_s })
    controller = VrpsController.new

    vrp_queries = []
    callback = ->(*args) { vrp_queries << args.last[:sql] if args.last[:sql].include?(%Q{FROM "vrps"}) }
    candidates = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      candidates = controller.send(:approval_candidate_vrps)
    end

    assert_equal [status_candidate.id, history_candidate.id].sort, candidates.map(&:id).sort
    assert_equal 1, vrp_queries.size
    assert_match(/SELECT.*"vrps"\."name".*"vrps"\."mobile_no"/m, vrp_queries.first)
    refute_match(/"vrps"\."address"/, vrp_queries.first)
  end

  test "plain hierarchy labels and registration enrichment share one user query" do
    User.create!(first_name: "Plain", last_name: "Coordinator", user_name: "plain_lookup_cc",
      email: "plain-lookup-cc@example.test", password: "secret", role: "Cluster Incharge", status: "Active")
    controller = VrpsController.new
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "users"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert controller.send(:user_record_cluster_incharge_label?, "Plain Coordinator")
      10.times { |index| assert_not controller.send(:user_record_cluster_incharge_label?, "Missing #{index}") }
      assert_equal "Plain Coordinator", controller.send(:enrich_cluster_mapping_from_user,
        { value: "plain_lookup_cc", label: "Saved" })[:value]
    end
    assert_equal 1, queries.size
  end

  test "cluster enrichment loads ordered users once and preserves inactive filtering" do
    User.create!(first_name: "Lookup", last_name: "Person", user_name: "lookup_person", email: "lookup_person@example.com", password: "secret", status: "Active")
    controller = VrpsController.new
    mapping = { value: "lookup_person", label: "Original" }
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "users"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      first = controller.send(:enrich_cluster_mapping_from_user, mapping)
      assert_equal "Lookup Person", first[:value]
      assert_equal first, controller.send(:enrich_cluster_mapping_from_user, mapping)
      assert_equal({ value: "missing", label: "Missing" }, controller.send(:enrich_cluster_mapping_from_user, { value: "missing", label: "Missing" }))
    end
    assert_equal 1, queries.size
  end

  test "module labels cache missing rows and preserve literal fallback" do
    controller = VrpsController.new
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "module_records"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      3.times { assert_equal "Unknown", controller.send(:module_record_label, "state-master", "Unknown", "state_name") }
    end
    assert_equal 1, queries.size
  end

  def create_test_vrp(name, attributes = {})
    vrp = Vrp.new({ name: name, aadhar_no: "123456789012", account_no: "123", address: "Test", branch: "Test",
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "performance-#{SecureRandom.hex(4)}@example.test", experience_in_years: 0,
      father_husband_name: "Test", gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210",
      office_detail_id: 0, to_office_detail_id: 0 }.merge(attributes))
    vrp.save!(validate: false)
    vrp
  end
end
