require "test_helper"

class JeevikaBillStaffScopeTest < ActiveSupport::TestCase
  setup do
    @mapped = create_vrp("Mapped", "FCO-C Sausar")
    @same_office = create_vrp("Office", "Sausar - FCO")
    @outside = create_vrp("Outside", "FCO-C Other")
  end

  test "CC sees only mapped JJ bills even when unrelated bill names them as creator" do
    controller = calculator("Cluster Coordinator")
    controller.define_singleton_method(:module_cluster_visible_vrp_ids) { [@mapped_id] }
    controller.instance_variable_set(:@mapped_id, @mapped.id)
    assert controller.send(:jeevika_jankar_bill_record_visible?, bill(@mapped))
    assert_not controller.send(:jeevika_jankar_bill_record_visible?, bill(@same_office))
    assert_not controller.send(:jeevika_jankar_bill_record_visible?, bill(@outside))
  end

  test "agronomist and FCOC see every JJ in their mapped office without creator fallback" do
    ["Agronomist", "FCO-C"].each do |role|
      controller = calculator(role)
      assert controller.send(:jeevika_jankar_bill_record_visible?, bill(@mapped))
      assert controller.send(:jeevika_jankar_bill_record_visible?, bill(@same_office))
      assert_not controller.send(:jeevika_jankar_bill_record_visible?, bill(@outside))
    end
  end

  test "admin sees all bills and FCO names display from JJ registration" do
    controller = calculator("Admin", admin: true)
    [@mapped, @same_office, @outside].each do |vrp|
      assert controller.send(:jeevika_jankar_bill_record_visible?, bill(vrp))
      assert_equal vrp.fcoc, controller.send(:jeevika_bill_fcoc_name, bill(vrp))
    end
    assert_includes ModulesController::MODULES.fetch("training-form-list")[:fields], "FCO Name"
  end

  test "office staff without an office get no unrelated bills" do
    controller = calculator("Agronomist")
    controller.instance_variable_set(:@current_app_user, { "role" => "Agronomist", "username" => "staff", "record_type" => "User" })
    assert_not controller.send(:jeevika_jankar_bill_record_visible?, bill(@mapped))
  end

  test "bill channel follows the live mapped cluster incharge rather than the creator or viewer" do
    owner = User.create!(user_name: "bill_channel_owner", first_name: "Akash", last_name: "Raut",
      password: "secret", stakeholder: "ASA", role: "Cluster Incharge", status: "Active")
    @mapped.update_columns(cluster_incharge: "Akash Raut (Cluster Incharge)")
    record = bill(@mapped)
    record.save!
    steps = 5.times.map do |index|
      ModuleRecord.create!(module_slug: "approval-master", data: {
        "module_name" => "Jeevika Jankar Bill", "stakeholder_name" => "ASA",
        "user_name" => "Akash Raut", "approval_level" => "Level #{index + 1}",
        "approver_approved_by" => "Approver #{index + 1}", "status" => "Active"
      })
    end

    assert_equal steps.map(&:id), calculator("Admin", admin: true).send(:jeevika_bill_approval_steps, record).map(&:id)

    @mapped.update_columns(cluster_incharge: "Another CC")
    User.create!(user_name: "another_bill_cc", first_name: "Another", last_name: "CC",
      password: "secret", stakeholder: "ASA", role: "Cluster Incharge", status: "Active")
    assert_empty calculator("Admin", admin: true).send(:jeevika_bill_approval_steps, record)
  end

  test "bill channel resolves a legacy mapped cluster incharge by username" do
    ModuleRecord.create!(module_slug: "new-user", data: {
      "user_name" => "legacy_bill_cc", "name" => "Legacy CC", "stakeholder" => "ASA", "status" => "Active"
    })
    @mapped.update_columns(cluster_incharge: "legacy_bill_cc")
    record = bill(@mapped)
    record.save!
    step = ModuleRecord.create!(module_slug: "approval-master", data: {
      "module_name" => "Jeevika Jankar Bill", "stakeholder_name" => "ASA",
      "user_name" => "Legacy CC", "approval_level" => "First Approval", "status" => "Active"
    })
    assert_equal [step.id], calculator("Admin", admin: true).send(:jeevika_bill_approval_steps, record).map(&:id)
  end

  test "compact training payload round trips repeated and conflicting farmer metadata exactly" do
    farmer = { id: "1", farmer_name: "A", record_missing: false }
    mappings = [{ farmer_ids: ["1"], farmers: [farmer] },
      { farmer_ids: ["1", "2"], farmers: [farmer, { id: "2", farmer_name: "B" }] },
      { farmer_ids: ["1"], farmers: [{ id: "1", farmer_name: "Legacy" }] }]
    controller = ModulesController.new
    controller.define_singleton_method(:training_target_mappings) { mappings }
    packed = controller.send(:training_target_browser_payload)
    assert_equal 3, packed[:farmers].size
    restored = packed[:mappings].map { |row| row.except(:farmer_indexes).merge(farmers: row[:farmer_indexes].map { |index| packed[:farmers][index] }) }
    assert_equal mappings, restored
    assert_equal farmer, mappings.first[:farmers].first
  end

  private

  def calculator(role, admin: false)
    controller = ModulesController.new
    controller.instance_variable_set(:@current_app_user, { "role" => role, "username" => "staff", "record_type" => "User", "fcoc" => "Sausar", "user_type" => admin ? "admin" : "user" })
    controller
  end

  def bill(vrp)
    ModuleRecord.new(module_slug: "jeevika-jankar-bill-process", data: { "select_vrp" => vrp.id.to_s, "created_by_username" => "staff" })
  end

  def create_vrp(name, fcoc)
    vrp = Vrp.new(name: name, fcoc: fcoc, aadhar_no: "123456789012", account_no: "123",
      address: "Test", branch: "Test", date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      email: "#{name}@example.test", experience_in_years: 0, father_husband_name: "Test",
      gender: 1, ifsc_code: "TEST0123456", mobile_no: "9876543210", office_detail_id: 0, to_office_detail_id: 0)
    vrp.save!(validate: false)
    vrp
  end
end
