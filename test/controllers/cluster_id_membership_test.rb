require "test_helper"

class ClusterIdMembershipTest < ActiveSupport::TestCase
  test "indexed cluster membership preserves exact string IDs and does not mutate the source" do
    ids = ["12", "012", "name", "12"]
    controller = ModulesController.new
    controller.define_singleton_method(:module_cluster_visible_vrp_id_strings) { ids }
    ["12", "012", "name", "", " 12 ", "absent", 12, nil].each do |id|
      assert_equal ids.include?(id), controller.send(:module_cluster_visible_vrp_id?, id)
    end
    assert_equal ["12", "012", "name", "12"], ids
  end
end
