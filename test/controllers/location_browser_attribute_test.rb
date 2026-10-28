require "test_helper"

# The location form embeds the whole location catalogue in a data attribute.
# The JSON was cached but its escaped form was not, so every location page
# rebuilt two fresh copies of a payload that is ~19MB in production - large
# enough on its own to cross Ruby's default 16MB malloc limit and force a
# stop-the-world major GC on each request.
#
# location_hierarchy_browser_attribute caches the escaped text under the same
# catalogue revision. These tests pin that what reaches the HTML is byte for
# byte what `<%= json_escape(location_hierarchy_browser_json) %>` produced, and
# that it still tracks changes to the masters.
class LocationBrowserAttributeTest < ActiveSupport::TestCase
  setup do
    @village = ModuleRecord.create!(module_slug: "village-master", data: {
      "village_name" => "Kalapan", "gram_panchayat_name" => "Kalapan GP",
      "state_name" => "MP", "district_name" => "Jhabua", "block_name" => "Ranapur"
    })
    # Characters that json_escape and html_escape both care about, so the two
    # escaping passes are actually exercised rather than passing through.
    @tricky = ModuleRecord.create!(module_slug: "village-master", data: {
      "village_name" => %(A<b>&"'</b>   B), "gram_panchayat_name" => "GP <&>",
      "state_name" => "MP", "district_name" => "Jhabua", "block_name" => "Ranapur"
    })
  end

  # Exactly what the view used to do.
  def previous_output(controller)
    ERB::Util.html_escape(ERB::Util.json_escape(controller.send(:location_hierarchy_browser_json)))
  end

  test "the attribute is byte for byte what the old escaping produced" do
    old = previous_output(ModulesController.new)
    new = ModulesController.new.send(:location_hierarchy_browser_attribute)

    assert_equal old.to_s, new.to_s,
      "the cached attribute does not match what the view rendered before"
  end

  test "it is html_safe so ERB does not escape it a second time" do
    attribute = ModulesController.new.send(:location_hierarchy_browser_attribute)

    assert_predicate attribute, :html_safe?
    # If ERB escaped it again the ampersands would become &amp;amp;.
    assert_equal attribute.to_s, ERB::Util.html_escape(attribute).to_s
  end

  test "the escaping actually did something to the tricky characters" do
    attribute = ModulesController.new.send(:location_hierarchy_browser_attribute).to_s

    assert_includes attribute, "&quot;", "quotes must be escaped for an HTML attribute"
    assert_not_includes attribute, "<b>", "raw markup survived into the attribute"
    assert_includes attribute, "u2028", "the line separator must stay JSON-escaped"
  end

  test "a second request reuses the cache instead of rebuilding" do
    # location_catalogue_cache deliberately uses Rails.cache under test so the
    # lifecycle stays observable, but the test environment configures a null
    # store - which caches nothing. Swap in a real one for this test only.
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ModulesController.new.send(:location_hierarchy_browser_attribute)

    queries = []
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      queries << sql if sql.match?(/FROM "module_records"/)
    end
    second = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      second = ModulesController.new.send(:location_hierarchy_browser_attribute)
    end

    assert_predicate second, :present?
    # The revision probe still runs; the catalogue itself must not be reread.
    assert_operator queries.size, :<=, 1,
      "the catalogue was rebuilt even though the revision had not changed"
  ensure
    Rails.cache = original if original
  end

  # This has to run against a real store. Under the test environment's null
  # store nothing is ever cached, so a stale-cache bug - say a key that left the
  # catalogue revision out - would pass unnoticed while silently freezing every
  # location dropdown in production.
  test "editing a master changes the attribute even with a live cache" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    before = ModulesController.new.send(:location_hierarchy_browser_attribute).to_s
    assert_includes before, "Kalapan"

    # update_column on purpose: imports and maintenance tasks bypass Rails
    # timestamps, and the xmin-based revision still has to notice.
    @village.update_column(:data, @village.data.merge("village_name" => "Kalapan Updated"))

    after = ModulesController.new.send(:location_hierarchy_browser_attribute).to_s
    assert_includes after, "Kalapan Updated",
      "a master edit did not reach the form, so the attribute cache is stale"
    assert_not_equal before, after
    assert_equal previous_output(ModulesController.new).to_s, after
  ensure
    Rails.cache = original if original
  end

  # The checks above run against the test environment's null store, so they
  # never exercise the cache round-trip that production actually uses. This one
  # does: the value has to come back out of a real store still byte-identical
  # and still safe to write without a second escaping pass.
  test "the value survives a real cache round-trip unchanged" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    expected = previous_output(ModulesController.new).to_s

    first = ModulesController.new.send(:location_hierarchy_browser_attribute)
    second = ModulesController.new.send(:location_hierarchy_browser_attribute)

    assert_equal expected, first.to_s
    assert_equal expected, second.to_s,
      "the value changed after it had been through the cache"
    assert_predicate second, :html_safe?,
      "the cached value came back unsafe, so ERB would escape it a second time"
    assert_equal second.to_s, ERB::Util.html_escape(second).to_s,
      "ERB would double-escape the cached value"
  ensure
    Rails.cache = original if original
  end

  test "it stays in step with the json it is built from" do
    controller = ModulesController.new
    json = controller.send(:location_hierarchy_browser_json)
    attribute = controller.send(:location_hierarchy_browser_attribute).to_s

    assert_equal ERB::Util.html_escape(ERB::Util.json_escape(json)).to_s, attribute
  end
end
