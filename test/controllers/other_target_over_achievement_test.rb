require "test_helper"

# Other Target with Farmer records whoever was actually worked with, and a
# village can hold more farmers than the mapped target, so doing more than
# planned is a real outcome rather than a mistake. The browser already skipped
# the cap for this one screen; the server still rejected the save, so the form
# could not be submitted. These tests pin that the cap is lifted there and kept
# on every other target module.
class OtherTargetOverAchievementTest < ActiveSupport::TestCase
  MAPPED_TARGET = { new_farmer_target: false }.freeze

  def controller_for(slug)
    controller = ModulesController.new
    controller.instance_variable_set(:@slug, slug)
    # The mapping lookup is a separate concern; this test is about the numbers.
    controller.define_singleton_method(:seed_distribution_target_match) { |_data| MAPPED_TARGET }
    controller
  end

  def payload(target:, achievement:, farmer_count: nil, farmer_ids: nil)
    count = farmer_count || [achievement.to_i, 0].max
    ids = farmer_ids || Array.new([count.to_i, 0].max) { |index| (index + 1).to_s }
    {
      "jeevika_jankar_id" => "40", "jeevika_jankar_name" => "Gita Korde",
      "month" => "October", "ics" => "ICS",
      "village" => "Kurmel", "training_topic" => "Internal Inspection",
      "training_subject" => "Farmer Internal Inspection",
      "completion_date" => "2026-10-31", "contact_number" => "9876543210",
      "target" => target.to_s, "achievement" => achievement.to_s,
      "farmer_count" => count.to_s, "selected_farmer_ids" => ids
    }
  end

  def errors_for(slug, **numbers)
    controller_for(slug).send(:seed_distribution_target_error_messages, payload(**numbers))
  end

  test "Other Target with Farmer accepts achievement above the target" do
    errors = errors_for("other-target-with-farmer", target: 56, achievement: 79)

    assert_not_includes errors, "Achievement Target se jyada nahi ho sakta.",
      "the one screen that is allowed to exceed its target was still blocked"
  end

  test "Other Target with Farmer accepts a farmer count above the target" do
    errors = errors_for("other-target-with-farmer", target: 56, achievement: 79, farmer_count: 79)

    assert_not_includes errors, "Farmer Count Target se jyada nahi ho sakta."
  end

  test "Other Target with Farmer saves cleanly when it exceeds the target" do
    assert_empty errors_for("other-target-with-farmer", target: 56, achievement: 79),
      "exceeding the target must not stop the save on this screen"
  end

  test "seed distribution target still caps achievement" do
    errors = errors_for("seed-distribution-target", target: 56, achievement: 79)

    assert_includes errors, "Achievement Target se jyada nahi ho sakta.",
      "the cap must stay on the other target modules"
  end

  test "papl360 target still caps achievement" do
    assert_includes errors_for("papl360-target", target: 56, achievement: 79),
      "Achievement Target se jyada nahi ho sakta."
  end

  test "the remaining checks still apply on Other Target with Farmer" do
    errors = errors_for("other-target-with-farmer", target: 56, achievement: -1)

    assert_includes errors, "Achievement zero se kam nahi ho sakta.",
      "lifting the cap must not switch off the rest of the validation"
  end

  test "farmer count must still match the farmers actually selected" do
    errors = errors_for("other-target-with-farmer", target: 56, achievement: 79,
      farmer_count: 79, farmer_ids: %w[1 2 3])

    assert_includes errors, "Farmer Count selected farmers ke count ke equal hona chahiye."
  end
end
