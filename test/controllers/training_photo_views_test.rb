require "test_helper"

class TrainingPhotoViewsTest < ActiveSupport::TestCase
  setup do
    @controller = ModulesController.new
    @controller.instance_variable_set(:@slug, "training-form")
    @controller.define_singleton_method(:normalize_training_form_data) { |data| data }
  end

  test "named views replace old input and keep report photo compatibility" do
    fields = ModulesController::MODULES.fetch("training-form")[:fields]
    assert_includes fields, "Training Register Upload"
    refute_includes fields, "Training Photo Upload with Geo Tag"
    TrainingEditApproval::PHOTO_VIEW_FIELDS.each do |key, label|
      assert_includes fields, label
      assert_equal key, label.parameterize(separator: "_")
    end
    @controller.params = ActionController::Parameters.new(module_record: {
      photo_front_view: "/uploads/module_records/front.png", photo_back_view: "/uploads/module_records/back.png"
    })
    data = @controller.send(:normalized_module_data)
    assert_equal ["/uploads/module_records/front.png", "/uploads/module_records/back.png"], data["training_photo_upload_with_geo_tag"]
    previous = { "training_photo_upload_with_geo_tag" => "/uploads/module_records/legacy.png" }
    merged = @controller.send(:preserve_training_uploads, previous, data)
    assert_includes merged["training_photo_upload_with_geo_tag"], previous["training_photo_upload_with_geo_tag"]
  end

  test "oversized and non-image named uploads fail before any file is stored" do
    upload = Struct.new(:original_filename, :size, :content_type)
    @controller.define_singleton_method(:module_records_required_for_show?) { false }
    @controller.define_singleton_method(:flash) { @test_flash ||= Struct.new(:now).new({}) }
    @controller.define_singleton_method(:render) { |*args, **kwargs| @rendered_status = kwargs[:status] }
    [[5.megabytes + 1, "image/png", "5 MB"], [100, "text/plain", "select an image"]].each do |size, type, message|
      f = upload.new("photo.png", size, type)
      @controller.define_singleton_method(:module_record_params) { { "photo_front_view" => [f] } }
      assert @controller.send(:reject_invalid_training_view_uploads)
      assert_match message, @controller.flash.now[:alert]
      assert_equal :unprocessable_entity, @controller.instance_variable_get(:@rendered_status)
    end

    six_files = Array.new(6) { upload.new("photo.png", 100, "image/png") }
    @controller.define_singleton_method(:module_record_params) { { "photo_front_view" => six_files } }
    assert @controller.send(:reject_invalid_training_view_uploads)
    assert_match "maximum 5 photos are allowed", @controller.flash.now[:alert]
  end
end
