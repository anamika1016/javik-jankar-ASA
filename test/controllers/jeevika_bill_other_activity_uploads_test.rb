require "test_helper"

class JeevikaBillOtherActivityUploadsTest < ActiveSupport::TestCase
  test "bill farmer display resolves names without changing saved bill data" do
    controller = ModulesController.new
    profile = Struct.new(:farmer_name, :village_name, :father_name, :tracenet_no).new("ANTARBAI", "Kosduna", "INDARSINGH", "890816455307")
    controller.define_singleton_method(:training_farmers_by_id) { |_ids| { "42" => profile } }
    record = Struct.new(:data).new({ "bill_items" => [{ "farmer_details" => [{ "id" => "42", "name" => "Farmer #42" }] }] })
    farmer = controller.send(:jeevika_bill_display_items, record).first["farmer_details"].first
    assert_equal "ANTARBAI", farmer["name"]
    assert_equal "Kosduna", farmer["village_name"]
    assert_equal "INDARSINGH", farmer["father_name"]
    assert_equal "890816455307", farmer["tracenet_no"]
    assert_equal "Farmer #42", record.data["bill_items"].first["farmer_details"].first["name"]
  end

  test "Other Target requires both upload fields including blank array submissions" do
    controller = ModulesController.new
    controller.define_singleton_method(:record_source_slug) { "other-target" }
    controller.define_singleton_method(:seed_distribution_target_match) { |_data| {} }
    [nil, "", [], ["", nil]].each do |blank_upload|
      data = { "attachment_upload" => blank_upload, "field_photo" => blank_upload }
      errors = controller.send(:seed_distribution_target_error_messages, data)
      assert_includes errors, "Attachment Upload required hai."
      assert_includes errors, "Field Photo required hai."
    end
    data = { "attachment_upload" => ["/uploads/module_records/evidence.xlsx"], "field_photo" => ["/uploads/module_records/photo.jpg"] }
    errors = controller.send(:seed_distribution_target_error_messages, data)
    refute_includes errors, "Attachment Upload required hai."
    refute_includes errors, "Field Photo required hai."
  end

  test "bill attachments include only matching active Other Target uploads" do
    controller = ModulesController.new
    controller.define_singleton_method(:module_upload_public_urls) { |value| Array(value).compact_blank }
    matching = ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => "12345", "attachment_upload" => ["/uploads/module_records/seed.xlsx"]
    })
    ModuleRecord.create!(module_slug: "other-target", data: {
      "target_mapping_id" => "54321", "attachment_upload" => ["/uploads/module_records/unrelated.xlsx"]
    })
    ModuleRecord.create!(module_slug: "papl360-target", data: {
      "target_mapping_id" => "12345", "deleted" => true,
      "attachment_upload" => ["/uploads/module_records/deleted.xlsx"]
    })

    assert_equal matching.data["attachment_upload"],
      controller.send(:jeevika_bill_other_activity_uploads, { "target_mapping_ids" => ["12345"] })
    assert_empty controller.send(:jeevika_bill_other_activity_uploads, {})
  end
end
