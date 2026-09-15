require "test_helper"

class AgreementVillageNameTest < ActiveSupport::TestCase
  test "preserves village names even when the integer profile village is zero" do
    vrp = Vrp.new(village_ids: ["Rampur", "123||Sundarpur"])
    vrp.build_vrp_profile(village_id: 0)
    assert_equal "Rampur, Sundarpur", AgreementVillageName.call(vrp)
  end

  test "looks up village codes without using unrelated module records" do
    unrelated = ModuleRecord.create!(module_slug: "month-master", data: { "name" => "July" })
    ModuleRecord.create!(module_slug: "village-master", data: { "village_code" => unrelated.id.to_s, "village_name" => "Rampur" })
    assert_equal "Rampur", AgreementVillageName.call(Vrp.new(village_ids: [unrelated.id]))
  end
end
