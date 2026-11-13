require "test_helper"

class ClusterRoleLabelIndexTest < ActiveSupport::TestCase
  test "indexed cluster roles preserve legacy matching including duplicate names and inactive users" do
    User.create!(first_name: "Index", last_name: "Person", user_name: "index_staff",
      email: "index-staff@example.test", password: "secret", role: "Staff", status: "Active")
    User.create!(first_name: "Index", last_name: "Person", user_name: "index_cc",
      email: "index-cc@example.test", password: "secret", role: "Cluster Incharge", status: "Inactive")
    User.create!(first_name: "Ordinary", last_name: "Person", user_name: "ordinary_staff",
      email: "ordinary-staff@example.test", password: "secret", role: "Staff", status: "Active")

    api_class = Class.new(ApplicationController) { include VrpAccess }
    [ModulesController.new, VrpsController.new, api_class.new].each do |controller|
      controller.define_singleton_method(:model_ready?) { |_name| true }
      users = User.order(:first_name, :last_name, :user_name).to_a
      labels = ["Index Person", " INDEX_CC (Cluster Incharge) ", "index_staff", "Ordinary Person", "missing", ""]
      normalize = if controller.is_a?(ModulesController)
        ->(value) { controller.send(:normalize_dashboard_user_label, value) }
      else
        ->(value) { controller.send(:normalize_approver_label, value) }
      end
      labels.each do |label|
        key = controller.is_a?(ModulesController) ? normalize.call(label.sub(/\s*\([^)]*\)\s*\z/, "")) : normalize.call(label)
        expected = users.any? do |user|
          values = if controller.is_a?(ModulesController)
            [user.full_name, user.user_name, user.respond_to?(:name) ? user.name : nil].compact_blank
          else
            [user.full_name.presence || user.user_name, user.user_name]
          end
          role = user.role_name.presence || user.role
          (!controller.is_a?(ModulesController) || key.present?) &&
            values.any? { |value| normalize.call(value) == key } && role.to_s.downcase.include?("cluster")
        end
        assert_equal expected, controller.send(:user_record_cluster_incharge_label?, label), "#{controller.class}: #{label.inspect}"
      end
      # All users were indexed on the first lookup, including previously unseen labels.
      users_ivar = controller.is_a?(ModulesController) ? :@dashboard_cluster_role_users : :@cluster_mapping_users
      controller.instance_variable_get(users_ivar).each do |user|
        user.define_singleton_method(:full_name) { raise "Repeated user scan" }
      end
      assert_not controller.send(:user_record_cluster_incharge_label?, "new missing label")
      assert controller.send(:user_record_cluster_incharge_label?, "Index Person")
      # No cross-request role state survives a persisted role change.
      User.find_by!(user_name: "index_cc").update!(role: "Staff", role_name: nil)
      fresh = controller.class.new
      fresh.define_singleton_method(:model_ready?) { |_name| true }
      assert_not fresh.send(:user_record_cluster_incharge_label?, "Index Person")
      User.find_by!(user_name: "index_cc").update!(role: "Cluster Incharge")
    end
  end
end
