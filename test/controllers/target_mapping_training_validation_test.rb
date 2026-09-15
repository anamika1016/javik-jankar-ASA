require "test_helper"

class TargetMappingTrainingValidationTest < Minitest::Test
  def controller_for(targets, training: true, village: false)
    controller = TargetMappingsController.new
    controller.params = ActionController::Parameters.new(target_mapping: { training_targets: targets })
    controller.define_singleton_method(:training_target_mode?) { training }
    controller.define_singleton_method(:village_target_mode?) { village }
    controller
  end

  def valid_targets
    { "opg_training" => "2", "week_wise_opg" => "2", "input_demo_inm" => "0", "input_demo_pm" => "0", "ffs" => "0" }
  end

  def test_missing_payload_and_all_blank_fields_are_rejected
    [nil, {}, valid_targets.transform_values { "" }].each do |targets|
      assert_match "Please fill", controller_for(targets).send(:training_target_opg_error)
    end
  end

  def test_each_training_field_is_required
    valid_targets.each_key do |key|
      targets = valid_targets.merge(key => " ")
      assert_match "Please fill", controller_for(targets).send(:training_target_opg_error)
    end
  end

  def test_explicit_zero_sub_targets_are_allowed
    assert_nil controller_for(valid_targets).send(:training_target_opg_error)
  end

  def test_hidden_training_fields_are_not_required
    assert_nil controller_for(nil, training: false).send(:training_target_opg_error)
    assert_nil controller_for(nil, village: true).send(:training_target_opg_error)
  end

  def test_invalid_numbers_and_incorrect_totals_are_rejected
    refute_nil controller_for(valid_targets.merge("ffs" => "-1")).send(:training_target_opg_error)
    refute_nil controller_for(valid_targets.merge("ffs" => "1")).send(:training_target_opg_error)
  end

  def test_cc_is_independent_of_breakdown_and_cannot_exceed_opg
    %w[0 1 2].each do |value|
      assert_nil controller_for(valid_targets.merge("cc" => value)).send(:training_target_opg_error)
    end
    %w[3 -1 0.5 nope].each do |value|
      assert_match "CC Target", controller_for(valid_targets.merge("cc" => value)).send(:training_target_opg_error)
    end
    controller = controller_for(valid_targets.merge("cc" => "2"))
    assert_equal "2", controller.send(:training_target_attributes)["cc_target"]
    refute controller.send(:selected_training_targets).any? { |name, _| name == "CC Target" }
  end
end
