require "test_helper"

class Api::V1::SeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = SecureRandom.hex(3)
    @soy = "Soybean#{@tag}"
    @moong = "Moong#{@tag}"
    record("seed-crop-master", "seed_crop_name" => @soy)
    record("seed-crop-master", "seed_crop_name" => @moong)
    record("seed-crop-master", "seed_crop_name" => "Old#{@tag}", "status" => "Inactive")
    record("seed-variety-master", "seed_crop" => @soy, "seed_variety_name" => "JS 9560")
    record("seed-variety-master", "seed_crop" => @soy, "seed_variety_name" => "JS 2034")
    record("seed-variety-master", "seed_crop" => @moong, "seed_variety_name" => "Virat")
    record("seed-variety-master", "seed_crop" => "Old#{@tag}", "seed_variety_name" => "Gone")
    @shown = record("seed-product-master", "seed_crop" => @soy, "seed_variety" => "JS 9560", "seed_brand_name" => "Mahabeej",
      "fpo" => ["Alpha FPO", "Beta FPO"], "supplier_company_name" => "Seeds Co", "description" => "Kharif",
      "product_photo_upload" => "/uploads/module_records/seed.png", "amount" => "1200", "amount_status" => "Active",
      "subsidy" => "300.50", "subsidy_status" => "Active")
    @hidden = record("seed-product-master", "seed_crop" => @soy, "seed_variety" => "JS 2034", "seed_brand_name" => "Other",
      "fpo" => ["Beta FPO"], "supplier_company_name" => "Agro Ltd", "amount" => "900", "amount_status" => "Inactive",
      "subsidy" => "100", "subsidy_status" => "Inactive")
    record("seed-product-master", "seed_crop" => @soy, "seed_variety" => "JS 9560", "seed_brand_name" => "Off",
      "fpo" => ["Alpha FPO"], "supplier_company_name" => "X", "status" => "Inactive")
    @user = User.create!(user_name: "seed_api_#{@tag}", password: "secret", first_name: "S", user_type: "admin", status: "Active")
  end

  def record(slug, data)
    ModuleRecord.create!(module_slug: slug, data: { "status" => "Active" }.merge(data))
  end

  def get_json(path, params = {})
    get path, params: params, headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(@user)}" }
    assert_response :success
    response.parsed_body
  end

  test "needs a login" do
    get "/api/v1/seed-products"
    assert_response :unauthorized
  end

  test "seed crops and their varieties, active only, by name or id" do
    crops = get_json("/api/v1/seed-crops")["seed_crops"].map { |row| row["name"] }
    assert_includes crops, @soy
    assert_not_includes crops, "Old#{@tag}"

    assert_equal ["JS 2034", "JS 9560"], get_json("/api/v1/seed-varieties", seed_crop: @soy)["seed_varieties"].map { |row| row["name"] }
    moong_id = ModuleRecord.where(module_slug: "seed-crop-master").find { |r| r.data["seed_crop_name"] == @moong }.id
    assert_equal ["Virat"], get_json("/api/v1/seed-varieties", seed_crop_id: moong_id)["seed_varieties"].map { |row| row["name"] }
    assert_empty get_json("/api/v1/seed-varieties", seed_crop: "Old#{@tag}")["seed_varieties"]
    assert_empty get_json("/api/v1/seed-varieties", seed_crop_id: 0)["seed_varieties"]
  end

  test "products carry every field and hide the amount and subsidy a farmer must not see" do
    products = get_json("/api/v1/seed-products", seed_crop: @soy)["seed_products"]
    assert_equal [@shown.id, @hidden.id].sort, products.map { |row| row["id"] }.sort

    shown = products.find { |row| row["id"] == @shown.id }
    assert_equal "JS 9560", shown["seed_variety"]
    assert_equal "Mahabeej", shown["seed_brand_name"]
    assert_equal ["Alpha FPO", "Beta FPO"], shown["fpo"]
    assert_equal "Seeds Co", shown["supplier_company_name"]
    assert_equal "http://www.example.com/uploads/module_records/seed.png", shown["photo_url"]
    assert_equal [true, "1200", true, "300.5"], shown.values_at("show_amount", "amount", "show_subsidy", "subsidy")

    hidden = products.find { |row| row["id"] == @hidden.id }
    assert_equal [false, nil, false, nil], hidden.values_at("show_amount", "amount", "show_subsidy", "subsidy")
  end

  test "products filter by variety and FPO, and one product can be fetched" do
    assert_equal [@shown.id], get_json("/api/v1/seed-products", seed_crop: @soy, seed_variety: "js 9560")["seed_products"].map { |row| row["id"] }
    assert_equal [@shown.id], get_json("/api/v1/seed-products", fpo: "alpha fpo", seed_crop: @soy)["seed_products"].map { |row| row["id"] }

    assert_equal "Mahabeej", get_json("/api/v1/seed-products/#{@shown.id}")["seed_product"]["seed_brand_name"]
    get "/api/v1/seed-products/0", headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(@user)}" }
    assert_response :not_found
  end

  test "seed-masters gives crops, varieties and products in one call" do
    soy = get_json("/api/v1/seed-masters")["seed_crops"].find { |row| row["name"] == @soy }
    js9560 = soy["seed_varieties"].find { |row| row["name"] == "JS 9560" }
    assert_equal [@shown.id], js9560["seed_products"].map { |row| row["id"] }
  end
end
