require "test_helper"

class CropMastersTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(user_name: "crop_admin", password: "secret", first_name: "Crop Admin", user_type: "admin", status: "Active")
    post login_path, params: { login: "crop_admin", password: "secret" }
    follow_redirect!
  end

  test "season, type and crop masters save in hierarchy and the crop form cascades types by season" do
    assert_difference("ModuleRecord.where(module_slug: 'crop-season-master').count", 2) do
      post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Kharif", status: "Active" } }
      post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Rabi", status: "Active" } }
    end

    get module_path("crop-type-master")
    assert_response :success
    assert_select "select[name='module_record[crop_season]'] option", text: "Kharif"

    assert_difference("ModuleRecord.where(module_slug: 'crop-type-master').count", 2) do
      post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Kharif", crop_type_name: "Cereal", status: "Active" } }
      post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Rabi", crop_type_name: "Pulse", status: "Active" } }
    end

    get module_path("crop-master")
    assert_response :success
    assert_select "[data-crop-form]"
    assert_select "select[data-crop-season-select]"
    assert_select "select[data-crop-type-select]"
    map = JSON.parse(css_select("[data-crop-form]").first["data-crop-type-map"])
    assert_includes map, { "season" => "Kharif", "type" => "Cereal" }
    assert_includes map, { "season" => "Rabi", "type" => "Pulse" }

    assert_difference("ModuleRecord.where(module_slug: 'crop-master').count", 1) do
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Paddy", status: "Active" } }
    end
    crop = ModuleRecord.where(module_slug: "crop-master").last
    assert_equal %w[Kharif Cereal Paddy], crop.data.values_at("crop_season", "crop_type", "crop_name")
  end

  test "crop masters reject blanks and duplicates" do
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Kharif", status: "Active" } }

    assert_no_difference("ModuleRecord.count") do
      post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: " kharif ", status: "Active" } }
    end
    assert_response :unprocessable_entity

    assert_no_difference("ModuleRecord.count") do
      post records_module_path("crop-type-master"), params: { module_record: { crop_season: "", crop_type_name: "Cereal", status: "Active" } }
    end
    assert_response :unprocessable_entity

    # Same type name under a different season is allowed.
    post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Kharif", crop_type_name: "Cereal", status: "Active" } }
    assert_difference("ModuleRecord.where(module_slug: 'crop-type-master').count", 1) do
      post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Rabi", crop_type_name: "Cereal", status: "Active" } }
    end

    # Editing a record without changing it is not a duplicate of itself.
    season = ModuleRecord.find_by(module_slug: "crop-season-master")
    patch module_record_path("crop-season-master", season), params: { module_record: { crop_season_name: "Kharif", status: "Active" } }
    assert_response :redirect
  end

  test "sidebar shows the Crop menu" do
    get module_path("crop-season-master")
    assert_select ".side-module summary", text: /Crop/
    assert_select "a.side-sub-link[href='#{module_path('crop-master')}']"
  end

  test "each crop master lists the records saved on it" do
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Kharif", status: "Active" } }
    post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Kharif", crop_type_name: "Cereal", status: "Active" } }
    post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Paddy", status: "Active" } }

    { "crop-season-master" => %w[Kharif], "crop-type-master" => %w[Kharif Cereal], "crop-master" => %w[Kharif Cereal Paddy] }.each do |slug, values|
      get module_path(slug)
      assert_response :success
      rows = css_select("table tbody tr").map { |tr| tr.text.squish }
      assert rows.any? { |row| values.all? { |value| row.include?(value) } }, "#{slug} should list #{values.join(' / ')}, got #{rows.inspect}"
    end
  end
end
