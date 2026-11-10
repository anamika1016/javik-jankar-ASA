require "test_helper"

class RequestLabelMatchCacheTest < ActiveSupport::TestCase
  test "cached matching preserves exact fuzzy short empty and role-suffix comparisons" do
    labels = [nil, "", "A", "ab", "abc", "Ram Kumar", "RAM  KUMAR", "Ram Kumar (CC)",
      "Ramm Kumar", "Ram Other", "Kumar Ram", "राम कुमार", "A.B. Kumar", "abc (CC) (Role)"]
    [ModulesController, VrpsController].each do |klass|
      controller = klass.new
      labels.product(labels).each do |left, right|
        expected = controller.send(:uncached_cluster_label_matches?, left, right)
        2.times { assert_equal expected, controller.send(:cluster_label_matches?, left, right), [klass, left, right].inspect }
      end
    end
  end

  test "false results are reused and input edits cannot corrupt cached comparisons" do
    [ModulesController, VrpsController].each do |klass|
      controller = klass.new
      calls = 0
      controller.define_singleton_method(:uncached_cluster_label_matches?) do |left, right|
        calls += 1
        super(left, right)
      end
      label = +"Other Person"
      2.times { assert_not controller.send(:cluster_label_matches?, label, "Ram Kumar") }
      assert_equal 1, calls
      label.replace("Ram Kumar")
      assert controller.send(:cluster_label_matches?, label, "Ram Kumar")
      assert_equal 2, calls
      assert_not controller.send(:cluster_label_matches?, "Other Person", "Ram Kumar")
      assert_equal 2, calls
    end
  end

  test "normalization remains mutable and caches stay bounded and request local" do
    [ModulesController, VrpsController].each do |klass|
      controller = klass.new
      method = klass == ModulesController ? :normalize_dashboard_user_label : :normalize_person_label
      label = +"Ram Kumar"
      controller.send(method, label).replace("changed")
      assert_equal "ram kumar", controller.send(method, label)
      label.replace("Other Person")
      assert_equal "other person", controller.send(method, label)
      4100.times { |i| controller.send(:cluster_label_matches?, "Person #{i}", "Unrelated") }
      assert_operator controller.instance_variable_get(:@person_label_matches).size, :<=, 4096
      assert_operator controller.instance_variable_get(:@normalized_person_labels).size, :<=, 4096
      fresh = klass.new
      assert_nil fresh.instance_variable_get(:@person_label_matches)
      assert_nil fresh.instance_variable_get(:@normalized_person_labels)
    end
  end

  test "deletion flags retain JSON scalar string and structured value behavior" do
    [UsersController, ModulesController, VrpsController].each do |klass|
      controller = klass.new
      [nil, false, true, 0, 1, " YES ", "true", "Deleted", "no", [], {}, ["yes"]].each do |value|
        expected = %w[1 true yes deleted].include?(value.to_s.strip.downcase)
        assert_equal expected, controller.send(:truthy_module_flag?, value)
      end
    end
  end
end
