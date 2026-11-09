require "test_helper"

# Farmers are fetched one village at a time, so a blank village in the API
# response can always be recovered from the village that was asked for.
class TargetMappingVillageFallbackTest < ActiveSupport::TestCase
  setup do
    @controller = TargetMappingsController.new
    Rails.cache.clear
  end

  teardown { Rails.cache.clear }

  def stub_api_rows(rows)
    @controller.define_singleton_method(:fetch_external_farmers) { |**| rows }
  end

  test "blank village names fall back to the selected village label" do
    ["-", "", nil, "NULL", "n/a"].each do |api_value|
      Rails.cache.clear
      stub_api_rows([{ id: "1", farmer_name: "Anita Majhi", father_name: "Ananta Majhi",
                       tracenet_no: "OR2606014862", village_name: api_value }])

      rows = @controller.send(:external_village_farmers_for, ["5558||Borbhatta"])

      assert_equal "Borbhatta", rows.first[:village_name],
        "expected the selected village to replace #{api_value.inspect}"
    end
  end

  test "a real village name from the API is never overwritten" do
    stub_api_rows([{ id: "1", farmer_name: "Anita Majhi", village_name: "ApiVillage" }])

    rows = @controller.send(:external_village_farmers_for, ["5558||Borbhatta"])

    assert_equal "ApiVillage", rows.first[:village_name]
  end

  test "each village keeps its own label when several are selected" do
    @controller.define_singleton_method(:fetch_external_farmers) do |**kwargs|
      [{ id: "f#{kwargs[:id]}", farmer_name: "Farmer #{kwargs[:id]}", village_name: "-" }]
    end

    rows = @controller.send(:external_village_farmers_for, ["5558||Borbhatta", "3929||Karlasoda"])

    assert_equal({ "f5558" => "Borbhatta", "f3929" => "Karlasoda" },
      rows.to_h { |row| [row[:id], row[:village_name]] })
  end

  test "an id with no label leaves the API value untouched" do
    stub_api_rows([{ id: "1", farmer_name: "Anita Majhi", village_name: "-" }])

    rows = @controller.send(:external_village_farmers_for, ["5558"])

    assert_equal "-", rows.first[:village_name]
  end

  test "village cache operations are batched and raw empty results are reusable" do
    original_cache = Rails.cache
    store = ActiveSupport::Cache::MemoryStore.new
    reads = 0
    writes = 0
    store.define_singleton_method(:read_multi) { |*keys, **options| reads += 1; super(*keys, **options) }
    store.define_singleton_method(:write_multi) { |values, **options| writes += 1; super(values, **options) }
    Rails.cache = store
    @controller.define_singleton_method(:fetch_external_farmers) do |**kwargs|
      kwargs[:id] == "7" ? [] : [{ id: kwargs[:id], farmer_name: "Farmer #{kwargs[:id]}", village_name: "-" }]
    end
    villages = (1..7).map { |id| "#{id}||Village #{id}" }
    first = @controller.send(:external_village_farmers_for, villages)
    assert_equal 6, first.size
    assert_equal 2, reads
    assert_equal 2, writes
    assert_equal "-", store.read(["asa-village-farmer-list", "1"]).first[:village_name]
    @controller.define_singleton_method(:fetch_external_farmers) { |**| raise "Warm cache must not fetch" }
    assert_equal first, @controller.send(:external_village_farmers_for, villages)
    assert_equal 4, reads
    assert_equal 2, writes
  ensure
    Rails.cache = original_cache
  end

  test "unavailable village results still raise and are not cached" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    stub_api_rows(nil)
    assert_raises(RuntimeError) { @controller.send(:external_village_farmers_for, ["1||Village"]) }
    refute Rails.cache.exist?(["asa-village-farmer-list", "1"])
  ensure
    Rails.cache = original_cache
  end
end
