require "test_helper"

class SeedMastersTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(user_name: "seed_admin", password: "secret", first_name: "Seed Admin", user_type: "admin", status: "Active")
    post login_path, params: { login: "seed_admin", password: "secret" }
    follow_redirect!
  end

  test "sidebar shows the Seed menu" do
    get module_path("seed-crop-master")
    assert_response :success
    assert_select "a[href='#{module_path("seed-crop-master")}']", text: "Seed Crop Name"
    assert_select "a[href='#{module_path("seed-variety-master")}']", text: "Seed Variety"
  end

  test "seed crop names feed the variety form, and both list what was saved" do
    post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: "Soybean", status: "Active" } }
    post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: "मक्का", status: "Active" } }
    post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: "Old Seed", status: "Inactive" } }
    assert_equal 3, ModuleRecord.where(module_slug: "seed-crop-master").count

    get module_path("seed-crop-master")
    rows = css_select("table tbody tr").map { |tr| tr.text.squish }
    assert rows.any? { |row| row.include?("Soybean") }
    assert rows.any? { |row| row.include?("मक्का") }
    assert_select "input[name='module_record[seed_crop_name]'][type=text]"

    get module_path("seed-variety-master")
    assert_response :success
    options = css_select("select[name='module_record[seed_crop]'] option").map { |option| option.text.strip }
    assert_includes options, "Soybean"
    assert_includes options, "मक्का"
    assert_not_includes options, "Old Seed"

    assert_difference("ModuleRecord.where(module_slug: 'seed-variety-master').count", 1) do
      post records_module_path("seed-variety-master"), params: { module_record: { seed_crop: "Soybean", seed_variety_name: "JS 9560", status: "Active" } }
    end
    get module_path("seed-variety-master")
    assert css_select("table tbody tr").any? { |tr| tr.text.include?("Soybean") && tr.text.include?("JS 9560") }
  end

  test "seed masters reject blanks and duplicates" do
    post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: "Soybean", status: "Active" } }
    assert_no_difference("ModuleRecord.where(module_slug: 'seed-crop-master').count") do
      post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: " soybean ", status: "Active" } }
      post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: "", status: "Active" } }
    end

    post records_module_path("seed-variety-master"), params: { module_record: { seed_crop: "Soybean", seed_variety_name: "JS 9560", status: "Active" } }
    assert_no_difference("ModuleRecord.where(module_slug: 'seed-variety-master').count") do
      post records_module_path("seed-variety-master"), params: { module_record: { seed_crop: "Soybean", seed_variety_name: "js 9560", status: "Active" } }
      post records_module_path("seed-variety-master"), params: { module_record: { seed_crop: "", seed_variety_name: "JS 2034", status: "Active" } }
    end
    # The same variety name under another seed crop is a different variety.
    post records_module_path("seed-crop-master"), params: { module_record: { seed_crop_name: "Moong", status: "Active" } }
    assert_difference("ModuleRecord.where(module_slug: 'seed-variety-master').count", 1) do
      post records_module_path("seed-variety-master"), params: { module_record: { seed_crop: "Moong", seed_variety_name: "JS 9560", status: "Active" } }
    end
  end
end
