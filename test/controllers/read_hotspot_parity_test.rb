require "test_helper"

class ReadHotspotParityTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "cached location select HTML preserves escaping selected disabled values and immediate edits" do
    helper = ApplicationController.helpers
    options = 120.times.map { |i| ["Village #{i} <&\"' ग्राम", i.to_s] }
    [nil, "3", ["2", "5"], { selected: ["1", "4"], disabled: ["6"] }].each do |selected|
      expected = helper.options_for_select(options, selected)
      2.times do
        actual = helper.cached_location_select_options(options, selected)
        assert_equal expected, actual
        assert_predicate actual, :html_safe?
      end
    end
    previous = helper.cached_location_select_options(options, "3")
    options.first[0] = "Changed <label>"
    actual = helper.cached_location_select_options(options, "3")
    refute_equal previous, actual
    assert_equal helper.options_for_select(options, "3"), actual
    actual << "Local mutation"
    assert_equal helper.options_for_select(options, "3"), helper.cached_location_select_options(options, "3")
  end

  test "warm large location selects skip repeated Rails option generation" do
    helper = ApplicationController.helpers
    options = 120.times.map { |i| ["Village #{i}", i.to_s] }
    calls = 0
    trace = TracePoint.new(:call) { |event| calls += 1 if event.method_id == :options_for_select }
    trace.enable { 3.times { helper.cached_location_select_options(options, "3") } }
    assert_equal 1, calls
  end

  test "user master reader retains exact cross-slug timestamp tie order and independent arrays" do
    timestamp = Time.current
    records = [ModuleRecord.new(id: 1, module_slug: "state-master", created_at: timestamp),
      ModuleRecord.new(id: 2, module_slug: "lg-directory-list", created_at: timestamp),
      ModuleRecord.new(id: 3, module_slug: "lg-directory-list", created_at: timestamp - 1)]
    controller = UsersController.new
    grouped = records.group_by(&:module_slug)
    controller.instance_variable_set(:@user_form_module_records, grouped)
    [%w[state-master lg-directory-list], %w[lg-directory-list state-master], %w[missing], %w[lg-directory-list]].each do |slugs|
      expected = slugs.flat_map { |slug| grouped.fetch(slug, []) }.sort_by(&:created_at).reverse
      assert_equal expected, controller.send(:user_form_module_records, slugs)
      controller.send(:user_form_module_records, slugs).clear
      assert_equal expected, controller.send(:user_form_module_records, slugs)
    end
  end

  test "reloading user form masters on the same controller refreshes sorted source rows" do
    row = ModuleRecord.create!(module_slug: "state-master", data: { "state_name" => "Before reload" })
    controller = UsersController.new
    controller.send(:preload_user_form_module_records!)
    assert_includes controller.send(:module_record_options, "state-master", "state_name"), "Before reload"
    row.update_columns(data: { "state_name" => "After reload" })
    controller.send(:preload_user_form_module_records!)
    values = controller.send(:module_record_options, "state-master", "state_name")
    assert_includes values, "After reload"
    refute_includes values, "Before reload"
  end

  test "indexed office lookup retains all duplicate aliases ID collisions and original preference" do
    previous = DashboardFcoDirectory::Store.offices
    offices = [
      { id: "995", name: "Shared", aliases: ["FCO-C Shared", "Alternate"], raw_name: "Shared" },
      { id: "13", name: "Shared", aliases: ["Shared"], raw_name: "Shared" },
      { id: "Shared", name: "Different", aliases: ["Other"], raw_name: "Different" }
    ]
    DashboardFcoDirectory::Store.offices = offices
    [nil, "", " 995 ", "13", "Shared", "FCO-C Shared", "Alternate", "Other", "Absent"].each do |value|
      key = AgreementVrpScope.office_key(value)
      expected = key.blank? ? [] : offices.select do |office|
        office[:id] == value.to_s.strip || [office[:name], *office[:aliases]].any? { |name| AgreementVrpScope.office_key(name) == key }
      end
      2.times { assert_equal expected, DashboardFcoDirectory.offices_for(value) }
    end
    DashboardFcoDirectory::Store.offices = offices.reverse
    assert_equal offices.reverse, DashboardFcoDirectory.offices_for("Shared")
  ensure
    DashboardFcoDirectory::Store.offices = previous
    DashboardFcoDirectory::Store.office_lookup = nil
  end

  test "field readers retain blank handling value types key priority and code fallback" do
    values = [nil, false, "", " \t", 0, 5, [], ["A"], {}, { "a" => 1 }, "123 / 4", "Village", "ग्राम"]
    random = Random.new(19)
    [ModulesController, UsersController, VrpsController].each do |klass|
      controller = klass.new
      150.times do
        data = %w[first second third fourth].index_with { values.sample(random: random) }
        record = ModuleRecord.new(data: data)
        keys = %w[first second third fourth missing]
        expected = keys.filter_map { |key| data[key].presence }.first
        actual = controller.send(:first_present_data, record, *keys)
        expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
        text = keys.filter_map { |key| data[key].to_s.strip.presence }
        expected = text.find { |value| !controller.send(:code_like_location_value?, value) } || text.first
        actual = controller.send(:first_non_code_data, record, *keys)
        expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
      end
    end
  end

  test "warm master pages instantiate only the visible page and preserve original sort and pagination" do
    45.times do |index|
      ModuleRecord.create!(module_slug: "village-master", created_at: index.minutes.ago,
        data: { "village_name" => "Village #{index % 8}", "status" => index.even? ? "Active" : "Inactive",
          "legacy" => { "kept" => index }, "attachment" => "x" * 1000 })
    end
    [-1, 1, 2, 3, 99].each do |page|
      baseline = calculator(page)
      original = baseline.send(:cached_location_master_records, "village-master")
        .sort_by { |row| baseline.send(:module_record_sort_value, row) }
      expected = baseline.send(:paginated_master_records, original).map(&:attributes)
      calculator(page).send(:module_records) # Warm sorted rows.
      controller = calculator(page)
      instantiated = 0
      callback = ->(*args) { instantiated += args.last[:record_count] }
      actual = nil
      ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") { actual = controller.send(:module_records) }
      assert_equal expected, actual.map(&:attributes)
      assert_operator instantiated, :<=, 15
      %i[@module_records_total_count @module_records_page_count @module_records_page].each do |name|
        assert_equal baseline.instance_variable_get(name), controller.instance_variable_get(name)
      end
    end
  end

  test "master page cache refreshes direct edits and deletes without leaking request mutations" do
    row = ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Before" })
    first = calculator.send(:module_records).find { |record| record.id == row.id }
    first.data["village_name"] = "Local mutation"
    assert_equal "Before", calculator.send(:module_records).find { |record| record.id == row.id }.data["village_name"]
    row.update_columns(data: { "village_name" => "After" })
    assert_equal "After", calculator.send(:module_records).find { |record| record.id == row.id }.data["village_name"]
    row.destroy!
    refute_includes calculator.send(:module_records).map(&:id), row.id
  end

  test "master search retains the original rendered-row matching" do
    ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Search village", "status" => "Inactive" })
    ["village", "Activate", "Delete", "absent"].each do |query|
      controller = calculator(1, query)
      original = controller.send(:cached_location_master_records, "village-master")
        .sort_by { |row| controller.send(:module_record_sort_value, row) }
      expected = controller.send(:paginated_master_records, original).map(&:attributes)
      assert_equal expected, calculator(1, query).send(:module_records).map(&:attributes)
    end
  end

  test "dropdown cache retains types scope order and refreshes direct writes and rollback" do
    row = ModuleRecord.create!(module_slug: "cache-source", data: { "primary" => ["Array"], "alias" => "Legacy" })
    scope = ModuleRecord.where(module_slug: "cache-source")
    read = -> { ModulesController.new.send(:projected_module_field_values, scope, %w[primary alias]) }
    assert_equal [["Array"], "Legacy"], read.call
    projections = []
    callback = ->(*args) { projections << args.last[:sql] if args.last[:sql].include?("json_build_array") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      local = read.call
      local.first << "Local change"
      assert_equal [["Array"], "Legacy"], read.call
    end
    assert_empty projections
    row.update_columns(data: { "primary" => 0, "alias" => false })
    assert_equal [0], read.call
    row.update_columns(data: { "primary" => "Second direct edit" })
    assert_equal ["Second direct edit"], read.call
    ModuleRecord.transaction(requires_new: true) do
      row.update_columns(data: { "primary" => "Rolled back" })
      assert_equal ["Rolled back"], read.call
      raise ActiveRecord::Rollback
    end
    assert_equal ["Second direct edit"], read.call
    assert_empty ModulesController.new.send(:projected_module_field_values, ModuleRecord.where(module_slug: "other"), %w[primary alias])
    row.destroy!
    assert_empty read.call
  end

  test "indexed visibility fallback preserves every alias first match ambiguity and source order" do
    controller = ModulesController.new
    owners = [Vrp.new(id: 1, name: "Shared Name", user_name: "first", mobile_no: "111"),
      Vrp.new(id: 2, name: "Shared Name", user_name: "second", mobile_no: "222"),
      Vrp.new(id: 3, name: "Other Name", user_name: "third", mobile_no: "333")]
    fields = %w[jeevika_jankar_id vrp_id jeevika_jankar_name vrp_name select_vrp trainer_contact trainer_name contact_number jeevika_jankar_contact]
    records = fields.flat_map do |key|
      [nil, "", "1", " FIRST ", "shared name", "222", "Other Name - 333", "absent"].map do |value|
        ModuleRecord.new(data: { key => value })
      end
    end
    records << ModuleRecord.new(data: { "trainer_name" => "Other Name", "contact_number" => "111" })
    [owners, owners.reverse, owners.index_by(&:id)].each do |population|
      rows = population.is_a?(Hash) ? population.values : population
      records.each do |record|
        expected = rows.find { |owner| controller.send(:target_record_matches_vrp?, record, owner) }
        actual = controller.send(:target_record_matching_vrp, record, population)
        expected.nil? ? assert_nil(actual) : assert_same(expected, actual)
      end
    end
  end

  private

  def calculator(page = 1, query = nil)
    ModulesController.new.tap do |controller|
      controller.request = ActionDispatch::TestRequest.create
      controller.params = ActionController::Parameters.new(slug: "village-master", page: page, q: query)
      controller.instance_variable_set(:@slug, "village-master")
      controller.instance_variable_set(:@module, ModulesController::MODULES.fetch("village-master"))
    end
  end
end
