require "test_helper"

class ModulesControllerTest < ActiveSupport::TestCase
  test "directory compaction removes parent rows covered by descendants" do
    controller = ModulesController.new
    rows = [
      { state: "Bihar" },
      { state: "Bihar", district: "Patna" },
      { state: "Bihar", district: "Patna", block: "Sampatchak" },
      { state: "Jharkhand" }
    ]

    compacted = controller.send(:compact_lg_directory_rows, rows)

    assert_equal [
      { state: "Bihar", district: "Patna", block: "Sampatchak" },
      { state: "Jharkhand" }
    ], compacted
  end

  test "directory compaction compares location names case insensitively" do
    controller = ModulesController.new
    rows = [
      { state: " Bihar " },
      { state: "bihar", district: "Gaya" }
    ]

    assert_equal [{ state: "bihar", district: "Gaya" }], controller.send(:compact_lg_directory_rows, rows)
  end

  test "directory compaction preserves rows with unrelated descendants" do
    controller = ModulesController.new
    rows = [
      { state: "Bihar", district: "Patna" },
      { state: "Bihar", district: "Gaya", block: "Gaya Town" },
      { state: "Jharkhand", district: "Ranchi", block: "Kanke" }
    ]

    assert_equal rows, controller.send(:compact_lg_directory_rows, rows)
  end
end
