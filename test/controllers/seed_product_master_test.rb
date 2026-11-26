require "test_helper"

class SeedProductMasterTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(user_name: "seed_product_admin", password: "secret", first_name: "SP Admin", user_type: "admin", status: "Active")
    post login_path, params: { login: "seed_product_admin", password: "secret" }
    follow_redirect!
    @tag = SecureRandom.hex(3)
    @fpo_a = "Alpha FPO #{@tag}"
    @fpo_b = "Beta FPO #{@tag}"
    [@fpo_a, @fpo_b].each_with_index do |fpo, index|
      Afl.new(fpo_name: fpo, fpo_id: "9#{index}").save!(validate: false)
    end
    ModuleRecord.create!(module_slug: "seed-crop-master", data: { "seed_crop_name" => "Soybean", "status" => "Active" })
    ModuleRecord.create!(module_slug: "seed-crop-master", data: { "seed_crop_name" => "Moong", "status" => "Active" })
    ModuleRecord.create!(module_slug: "seed-variety-master", data: { "seed_crop" => "Soybean", "seed_variety_name" => "JS 9560", "status" => "Active" })
    ModuleRecord.create!(module_slug: "seed-variety-master", data: { "seed_crop" => "Moong", "seed_variety_name" => "Virat", "status" => "Active" })
  end

  def product(overrides = {})
    { seed_crop: "Soybean", seed_variety: "JS 9560", seed_brand_name: "Mahabeej", fpo: [@fpo_a, @fpo_b],
      supplier_company_name: "Seeds Co", description: "Kharif ke liye", amount: "1200", amount_status: "Active",
      subsidy: "300.50", subsidy_status: "Inactive", status: "Active" }.merge(overrides)
  end

  test "the form has every field, FPO as a multi-select and varieties mapped to their seed crop" do
    get module_path("seed-product-master")
    assert_response :success
    assert_select "a[href='#{module_path("seed-product-master")}']", text: "Seed Product Name"
    assert_select "select[name='module_record[seed_crop]'][data-seed-product-crop-select] option", text: "Soybean"
    assert_select "select[name='module_record[seed_variety]'][data-seed-product-variety-select]"
    assert_select "select[name='module_record[fpo][]'][multiple] option", text: @fpo_a
    assert_select "input[name='module_record[seed_brand_name]'][type=text]"
    assert_select "input[name='module_record[supplier_company_name]'][type=text]"
    assert_select "textarea[name='module_record[description]']"
    assert_select "input[name='module_record[product_photo_upload]'][type=file][accept='image/*']"
    assert_select ".seed-amount-row input[name='module_record[amount]'][type=number] ~ label.seed-show-farmer-check input[type=checkbox][name='module_record[amount_status]']"
    assert_select ".seed-amount-row input[name='module_record[subsidy]'][type=number] ~ label.seed-show-farmer-check input[type=checkbox][name='module_record[subsidy_status]']"
    form_labels = css_select("#module-form label > span").map { |span| span.text.squish }
    assert_not_includes form_labels, "Amount Status"
    assert_not_includes form_labels, "Subsidy Status"
    assert_select "input[name='module_record[subsidy]'][type=number]"
    %w[amount_status subsidy_status].each do |key|
      assert_select "input[type=hidden][name='module_record[#{key}]'][value=Inactive]"
      assert_select "input[type=checkbox][name='module_record[#{key}]'][value=Active]"
      assert_select "input[type=checkbox][name='module_record[#{key}]'][checked]", count: 0
      assert_select "select[name='module_record[#{key}]']", count: 0
    end
    map = JSON.parse(css_select("[data-seed-product-form]").first["data-seed-variety-map"])
    assert_includes map, { "crop" => "Soybean", "variety" => "JS 9560" }
    assert_includes map, { "crop" => "Moong", "variety" => "Virat" }
  end

  test "a seed product saves with several FPOs, a photo and its show-to-farmer switches, and is listed" do
    photo = Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png")
    assert_difference("ModuleRecord.where(module_slug: 'seed-product-master').count", 1) do
      post records_module_path("seed-product-master"), params: { module_record: product(product_photo_upload: photo) }
    end
    record = ModuleRecord.where(module_slug: "seed-product-master").last
    assert_equal [@fpo_a, @fpo_b], record.data["fpo"]
    assert_equal %w[1200 Active 300.50 Inactive], record.data.values_at("amount", "amount_status", "subsidy", "subsidy_status")
    assert record.data["product_photo_upload"].present?

    get module_path("seed-product-master")
    row = css_select("#module_saved_records tbody tr").map { |tr| tr.text.squish }.find { |text| text.include?("Mahabeej") }
    assert row, "saved product should be listed"
    ["Soybean", "JS 9560", "#{@fpo_a}, #{@fpo_b}", "Seeds Co", "1200", "300.50", "View", "Dikhega", "Nahi dikhega"].each { |text| assert_includes row, text }
  ensure
    FileUtils.rm_f(Rails.root.join("public", record.data["product_photo_upload"].to_s.delete_prefix("/"))) if record&.data&.[]("product_photo_upload").is_a?(String)
  end

  test "required fields, numbers and duplicates are checked" do
    assert_no_difference("ModuleRecord.where(module_slug: 'seed-product-master').count") do
      post records_module_path("seed-product-master"), params: { module_record: product(fpo: [""]) }
      post records_module_path("seed-product-master"), params: { module_record: product(seed_brand_name: "") }
      post records_module_path("seed-product-master"), params: { module_record: product(amount: "12abc") }
    end
    post records_module_path("seed-product-master"), params: { module_record: product }
    assert_no_difference("ModuleRecord.where(module_slug: 'seed-product-master').count") do
      post records_module_path("seed-product-master"), params: { module_record: product(seed_brand_name: " mahabeej ") }
    end
    assert_difference("ModuleRecord.where(module_slug: 'seed-product-master').count", 1) do
      post records_module_path("seed-product-master"), params: { module_record: product(seed_brand_name: "Other Brand", amount: "", subsidy: "") }
    end
  end

  test "editing keeps the chosen FPOs selected and the photo when no new one is sent" do
    record = ModuleRecord.create!(module_slug: "seed-product-master", data: product.transform_keys(&:to_s).merge("fpo" => [@fpo_b], "product_photo_upload" => "/uploads/module_records/old.png"))
    get edit_module_record_path("seed-product-master", record)
    assert_response :success
    assert_select "select[name='module_record[fpo][]'] option[selected]", text: @fpo_b
    assert_select "select[name='module_record[fpo][]'] option[selected]", text: @fpo_a, count: 0

    patch module_record_path("seed-product-master", record), params: { module_record: product(fpo: [@fpo_a], amount: "1500") }
    record.reload
    assert_equal [@fpo_a], record.data["fpo"]
    assert_equal "1500", record.data["amount"]
    assert_equal "/uploads/module_records/old.png", record.data["product_photo_upload"]
  end

  test "the show-to-farmer tick boxes save Active when ticked and Inactive when not" do
    post records_module_path("seed-product-master"), params: { module_record: product(amount_status: %w[Inactive Active], subsidy_status: "Inactive") }
    record = ModuleRecord.where(module_slug: "seed-product-master").last
    assert_equal %w[Active Inactive], record.data.values_at("amount_status", "subsidy_status")

    get edit_module_record_path("seed-product-master", record)
    assert_select "input[type=checkbox][name='module_record[amount_status]'][checked]"
    assert_select "input[type=checkbox][name='module_record[subsidy_status]'][checked]", count: 0
  end

  test "amount and subsidy are not shown to farmers unless ticked" do
    post records_module_path("seed-product-master"), params: { module_record: product.except(:amount_status, :subsidy_status) }
    record = ModuleRecord.where(module_slug: "seed-product-master").last
    assert_equal %w[Inactive Inactive], record.data.values_at("amount_status", "subsidy_status")
  end
end
