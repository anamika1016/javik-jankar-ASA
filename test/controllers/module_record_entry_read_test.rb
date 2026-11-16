require "test_helper"

class ModuleRecordEntryReadTest < ActionDispatch::IntegrationTest
  module ReadGuard
    def module_records
      raise "Unused sibling list was loaded" if Thread.current[:guard_entry_sibling_reads]
      super
    end
  end
  ModulesController.prepend(ReadGuard)

  setup do
    admin = User.create!(user_name: "entry_read_admin", password: "secret", first_name: "Admin",
      user_type: "admin", status: "Active")
    post login_path, params: { login: admin.user_name, password: "secret" }
  end

  teardown { Thread.current[:guard_entry_sibling_reads] = nil }

  test "entry and edit forms render selected values without loading sibling lists" do
    Thread.current[:guard_entry_sibling_reads] = true
    %w[other-target other-target-with-farmer seed-distribution-target papl360-target access-control approval-master vrp-bill-add jeevika-jankar-bill-process jeevika-jankar-transfer].each do |slug|
      get module_path(slug)
      assert_response :success, slug
      record = ModuleRecord.create!(module_slug: slug, data: { "status" => "Active", "activity" => "Selected Activity" })
      get edit_module_record_path(slug, record)
      assert_response :success, slug
      assert_select "form[action='#{module_record_path(slug, record)}']", minimum: 1
      assert_select "#module_saved_records", count: 0
    end
  end

  test "real saved-record screens still request their rows on entry and edit" do
    controller = ModulesController.new
    controller.params = ActionController::Parameters.new
    %w[month-master project-master add-farmer-form user-hierarchy-mapping state-master].each do |slug|
      controller.instance_variable_set(:@slug, slug)
      controller.instance_variable_set(:@record, nil)
      assert controller.send(:module_records_required_for_show?), slug
      controller.instance_variable_set(:@record, ModuleRecord.new(module_slug: slug))
      assert controller.send(:module_records_required_for_show?), slug
    end
  end
end
