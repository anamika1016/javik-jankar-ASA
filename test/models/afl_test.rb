require "test_helper"

class AflTest < ActiveSupport::TestCase
  test "search matches fields outside the list table columns" do
    marker = SecureRandom.hex(6)
    afl = Afl.create!(
      farmer_name: "Farmer #{marker}",
      purchase_product_type: "Hidden #{marker}"
    )

    assert_includes Afl.search("Hidden #{marker}"), afl
  end
end
