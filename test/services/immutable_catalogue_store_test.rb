require "test_helper"

class ImmutableCatalogueStoreTest < ActiveSupport::TestCase
  test "hits reuse a deeply immutable snapshot and caller copies remain independent" do
    cache = ImmutableCatalogueStore.new(size: 1.megabyte)
    cache.write("rows", [{ "name" => String.new("Before"), "ids" => [1, 2] }])
    first = cache.read("rows")
    assert_same first, cache.read("rows")
    assert_predicate first, :frozen?
    assert_predicate first.first, :frozen?
    assert_predicate first.first["name"], :frozen?
    assert_raises(FrozenError) { first.first["name"].replace("Mutation") }
    copy = first.deep_dup
    copy.first["name"].replace("Request-local")
    assert_equal "Before", cache.read("rows").first["name"]
  end

  test "expiry versions and bounded retention continue to work" do
    cache = ImmutableCatalogueStore.new(size: 2000)
    cache.write("versioned", ["value"], version: "one", expires_in: 1.second)
    assert_equal ["value"], cache.read("versioned", version: "one")
    assert_nil cache.read("versioned", version: "two")
    travel 2.seconds do
      assert_nil cache.read("versioned", version: "one")
    end
    20.times { |i| cache.write("rows-#{i}", [String.new("x" * 250)]) }
    assert_operator cache.instance_variable_get(:@cache_size), :<=, 2000
    assert_operator cache.instance_variable_get(:@data).size, :<, 20
  end

  test "cyclic snapshots can be measured and frozen without recursion loops" do
    cache = ImmutableCatalogueStore.new
    rows = []
    rows << rows
    cache.write("cycle", rows)
    assert_same rows, cache.read("cycle").first
    assert_predicate rows, :frozen?
  end
end
