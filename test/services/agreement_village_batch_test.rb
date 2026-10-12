require "test_helper"

class AgreementVillageBatchTest < ActiveSupport::TestCase
  test "batch preserves direct IDs aliases literal labels and missing fallbacks with bounded queries" do
    direct = ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Direct" })
    ModuleRecord.create!(module_slug: "lg-directory-list", data: { "village_id" => "900123", "village_name" => "First Alias" })
    ModuleRecord.create!(module_slug: "village-master", data: { "village_code" => "900123", "village_name" => "Later Alias" })
    vrps = 40.times.map do
      Vrp.new(village_ids: [direct.id.to_s, "900123", "99999999", "101||Literal", "Text Village", " "])
    end
    queries = []
    callback = ->(*args) do
      payload = args.last
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT")
    end
    expected = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      vrps.map { |vrp| AgreementVillageName.call(vrp) }
    end
    original_query_count = queries.size
    queries.clear
    actual = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      resolver = AgreementVillageName.new.preload(vrps)
      vrps.map { |vrp| resolver.call(vrp) }
    end
    assert_equal expected, actual
    assert_operator queries.size, :<=, 4
    assert_operator original_query_count, :>, queries.size * 40
    assert_includes actual.first, "First Alias"
  end

  test "blank village lists still use the preloaded profile village" do
    village = ModuleRecord.create!(module_slug: "village-master", data: { "village" => "Profile Village" })
    vrp = Vrp.new(village_ids: [])
    vrp.build_vrp_profile(village_id: village.id)
    assert_equal AgreementVillageName.call(vrp), AgreementVillageName.new.preload([vrp]).call(vrp)
  end

  test "leading zero IDs and blank earliest aliases preserve original precedence" do
    village = ModuleRecord.create!(module_slug: "village-master", data: { "village_name" => "Direct Village" })
    ModuleRecord.create!(module_slug: "village-master", data: { "village_id" => "900125", "village_name" => " " })
    ModuleRecord.create!(module_slug: "lg-directory-list", data: { "village_code" => "900125", "village_name" => "Later Name" })
    vrp = Vrp.new(village_ids: ["000#{village.id}", "900125", "#{village.id}||", "#{village.id}|| "])
    expected = AgreementVillageName.call(vrp)
    assert_equal "Direct Village, 900125", expected
    assert_equal expected, AgreementVillageName.new.preload([vrp]).call(vrp)
  end
end
