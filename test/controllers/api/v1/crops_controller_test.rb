require "test_helper"

class Api::V1::CropsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = SecureRandom.hex(3)
    @kharif = "Kharif#{@tag}"
    @rabi = "Rabi#{@tag}"
    @old = "Old#{@tag}"
    season(@kharif)
    season(@rabi)
    season(@old, status: "Inactive")
    @cereal = type(@kharif, "Cereal")
    type(@kharif, "Pulse")
    type(@rabi, "Oilseed")
    type(@old, "Gone")
    crop(@kharif, "Cereal", "Paddy")
    crop(@kharif, "Cereal", "Maize")
    crop(@kharif, "Pulse", "Moong")
    crop(@rabi, "Oilseed", "Mustard")
    crop(@kharif, "Cereal", "Hidden", status: "Inactive")
    @user = User.create!(user_name: "crop_api_#{@tag}", password: "secret", first_name: "C", user_type: "admin", status: "Active")
  end

  def season(name, status: "Active")
    ModuleRecord.create!(module_slug: "crop-season-master", data: { "crop_season_name" => name, "status" => status })
  end

  def type(season, name, status: "Active")
    ModuleRecord.create!(module_slug: "crop-type-master", data: { "crop_season" => season, "crop_type_name" => name, "status" => status })
  end

  def crop(season, type, name, status: "Active", grade: nil)
    ModuleRecord.create!(module_slug: "crop-master", data: { "crop_season" => season, "crop_type" => type, "crop_name" => name, "grade" => grade, "status" => status }.compact)
  end

  def get_json(path, params = {})
    get path, params: params, headers: { "Authorization" => "Bearer #{ApiAuthToken.encode(@user)}" }
    assert_response :success
    response.parsed_body
  end

  test "needs a login" do
    get "/api/v1/crop-seasons"
    assert_response :unauthorized
  end

  test "seasons list only active seasons" do
    names = get_json("/api/v1/crop-seasons")["crop_seasons"].map { |row| row["name"] }
    assert_includes names, @kharif
    assert_includes names, @rabi
    assert_not_includes names, @old
  end

  test "types follow the chosen season, by name or id" do
    by_name = get_json("/api/v1/crop-types", crop_season: @kharif)["crop_types"]
    assert_equal %w[Cereal Pulse], by_name.map { |row| row["name"] }
    assert by_name.all? { |row| row["crop_season"] == @kharif }

    season_id = ModuleRecord.where(module_slug: "crop-season-master").find { |r| r.data["crop_season_name"] == @rabi }.id
    assert_equal %w[Oilseed], get_json("/api/v1/crop-types", crop_season_id: season_id)["crop_types"].map { |row| row["name"] }
    assert_empty get_json("/api/v1/crop-types", crop_season: @old)["crop_types"]
    assert_empty get_json("/api/v1/crop-types", crop_season_id: 0)["crop_types"]
  end

  test "crops follow the chosen season and type, active only" do
    crops = get_json("/api/v1/crops", crop_season: @kharif, crop_type: "cereal")["crops"]
    assert_equal %w[Maize Paddy], crops.map { |row| row["name"] }
    assert_equal [@kharif], crops.map { |row| row["crop_season"] }.uniq

    assert_equal %w[Moong], get_json("/api/v1/crops", crop_season: @kharif, crop_type_id: ModuleRecord.where(module_slug: "crop-type-master").find { |r| r.data["crop_type_name"] == "Pulse" && r.data["crop_season"] == @kharif }.id)["crops"].map { |row| row["name"] }
  end

  test "crops carry their grade, one row per grade" do
    crop(@rabi, "Oilseed", "Mustard", grade: "B")
    ModuleRecord.where(module_slug: "crop-master").find { |r| r.data["crop_name"] == "Mustard" && r.data["grade"].blank? }.tap { |r| r.update!(data: r.data.merge("grade" => "A")) }

    crops = get_json("/api/v1/crops", crop_season: @rabi, crop_type: "Oilseed")["crops"]
    assert_equal [%w[Mustard A], %w[Mustard B]], crops.map { |row| row.values_at("name", "grade") }.sort
    tree_crops = get_json("/api/v1/crop-masters")["crop_seasons"].find { |row| row["name"] == @rabi }["crop_types"].first["crops"]
    assert_equal %w[A B], tree_crops.map { |row| row["grade"] }.sort
  end

  test "crop-masters gives season, types and crops in one call" do
    tree = get_json("/api/v1/crop-masters")["crop_seasons"]
    kharif = tree.find { |row| row["name"] == @kharif }
    assert_equal %w[Cereal Pulse], kharif["crop_types"].map { |row| row["name"] }
    assert_equal %w[Maize Paddy], kharif["crop_types"].first["crops"].map { |row| row["name"] }
    assert_nil tree.find { |row| row["name"] == @old }
  end
end
