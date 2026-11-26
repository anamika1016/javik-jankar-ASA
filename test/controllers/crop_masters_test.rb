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
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Paddy", grade: "A", status: "Active" } }
    end
    crop = ModuleRecord.where(module_slug: "crop-master").last
    assert_equal %w[Kharif Cereal Paddy A], crop.data.values_at("crop_season", "crop_type", "crop_name", "grade")
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

  test "a crop needs a grade, and is saved once per grade" do
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Kharif", status: "Active" } }
    post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Kharif", crop_type_name: "Cereal", status: "Active" } }

    get module_path("crop-master")
    assert_select "input[name='module_record[grade]']"

    assert_no_difference("ModuleRecord.where(module_slug: 'crop-master').count") do
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Wheat", grade: "", status: "Active" } }
    end
    assert_response :unprocessable_entity
    assert_match "Grade", response.body

    assert_difference("ModuleRecord.where(module_slug: 'crop-master').count", 2) do
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Wheat", grade: "A", status: "Active" } }
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Wheat", grade: "B", status: "Active" } }
    end

    assert_no_difference("ModuleRecord.where(module_slug: 'crop-master').count") do
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: " wheat ", grade: " a ", status: "Active" } }
    end
    assert_response :unprocessable_entity
    assert_match "wheat (Grade a)", response.body
  end

  test "several grades typed together save one crop row per grade" do
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Rabi", status: "Active" } }
    post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Rabi", crop_type_name: "Cereal", status: "Active" } }
    crops = -> { ModuleRecord.where(module_slug: "crop-master").select { |r| r.data["crop_name"] == "Wheat" }.map { |r| r.data["grade"] }.sort }

    get module_path("crop-master")
    assert_select "[data-crop-grades] input[name='module_record[grade]'][data-crop-grade-input]"
    assert_select "[data-crop-grades] button[data-add-crop-grade]", text: "+ Add Grade"

    post records_module_path("crop-master"), params: { module_record: { crop_season: "Rabi", crop_type: "Cereal", crop_name: "Wheat", grade: "A, B; C, b", status: "Active" } }
    assert_redirected_to module_path("crop-master")
    assert_equal "Crop saved for Grade A, B, C.", flash[:notice]
    assert_equal %w[A B C], crops.()

    # Grades already saved are skipped; the new one is added.
    post records_module_path("crop-master"), params: { module_record: { crop_season: "Rabi", crop_type: "Cereal", crop_name: "Wheat", grade: "c, D", status: "Active" } }
    assert_match "saved for Grade D", flash[:notice]
    assert_match "Grade c pehle se saved tha", flash[:notice]
    assert_equal %w[A B C D], crops.()

    # All of them already saved: nothing new, and the maker is told.
    assert_no_difference("ModuleRecord.where(module_slug: 'crop-master').count") do
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Rabi", crop_type: "Cereal", crop_name: "Wheat", grade: "A, B", status: "Active" } }
    end
    assert_response :unprocessable_entity
    assert_match "Grade A, B pehle se saved hai", response.body

    # A missing field stops all of them.
    assert_no_difference("ModuleRecord.where(module_slug: 'crop-master').count") do
      post records_module_path("crop-master"), params: { module_record: { crop_season: "Rabi", crop_type: "", crop_name: "Barley", grade: "A, B", status: "Active" } }
    end
    assert_response :unprocessable_entity

    # Editing keeps one grade per row.
    record = ModuleRecord.where(module_slug: "crop-master").find { |r| r.data["crop_name"] == "Wheat" && r.data["grade"] == "A" }
    patch module_record_path("crop-master", record), params: { module_record: { crop_season: "Rabi", crop_type: "Cereal", crop_name: "Wheat", grade: "A, E", status: "Active" } }
    assert_response :unprocessable_entity
    assert_match "ek hi Grade", response.body
    assert_equal "A", record.reload.data["grade"]
  end

  test "status is an Active switch beside Save, on by default" do
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Zaid", status: "Active" } }

    get module_path("crop-season-master")
    assert_select ".module-form-actions .status-switch input[type=checkbox][name='module_record[status]'][value=Active][checked]"
    assert_select ".module-form-actions input[type=hidden][name='module_record[status]'][value=Inactive]"
    assert_select ".module-form-grid select[name='module_record[status]']", count: 0

    # Switch off: only the hidden Inactive is sent.
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Summer", status: "Inactive" } }
    record = ModuleRecord.where(module_slug: "crop-season-master").find { |r| r.data["crop_season_name"] == "Summer" }
    assert_equal "Inactive", record.data["status"]
    get edit_module_record_path("crop-season-master", record)
    assert_select ".status-switch input[type=checkbox]:not([checked])"
  end

  test "sidebar shows the Crop menu" do
    get module_path("crop-season-master")
    assert_select ".side-module summary", text: /Crop/
    assert_select "a.side-sub-link[href='#{module_path('crop-master')}']"
  end

  test "each crop master lists the records saved on it" do
    post records_module_path("crop-season-master"), params: { module_record: { crop_season_name: "Kharif", status: "Active" } }
    post records_module_path("crop-type-master"), params: { module_record: { crop_season: "Kharif", crop_type_name: "Cereal", status: "Active" } }
    post records_module_path("crop-master"), params: { module_record: { crop_season: "Kharif", crop_type: "Cereal", crop_name: "Paddy", grade: "A", status: "Active" } }

    { "crop-season-master" => %w[Kharif], "crop-type-master" => %w[Kharif Cereal], "crop-master" => %w[Kharif Cereal Paddy A] }.each do |slug, values|
      get module_path(slug)
      assert_response :success
      rows = css_select("table tbody tr").map { |tr| tr.text.squish }
      assert rows.any? { |row| values.all? { |value| row.include?(value) } }, "#{slug} should list #{values.join(' / ')}, got #{rows.inspect}"
    end
  end
end
