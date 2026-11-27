require "test_helper"

class UnitMasterTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(user_name: "unit_admin", password: "secret", first_name: "Unit Admin", user_type: "admin", status: "Active")
    post login_path, params: { login: "unit_admin", password: "secret" }
    follow_redirect!
  end

  test "Unit Master has its own Unit menu, a name field and the Status switch" do
    get module_path("unit-master")
    assert_response :success
    assert_select "a[href='#{module_path("unit-master")}']", text: "Unit Master"
    assert_select "input[name='module_record[unit_name]'][type=text]"
    assert_select ".module-form-actions input[type=checkbox][name='module_record[status]']"
    assert_select ".module-hero .vrp-eyebrow", text: "Unit"
    assert_select ".module-hero p:not(.vrp-eyebrow)", count: 0
    get module_path("seed-product-master")
    seed_links = css_select("a").select { |a| a["href"] == module_path("unit-master") }
    assert_equal 1, seed_links.size, "Unit Master should appear once, in its own menu"
  end

  test "units save, are listed, and blanks or duplicates are rejected" do
    assert_difference("ModuleRecord.where(module_slug: 'unit-master').count", 2) do
      post records_module_path("unit-master"), params: { module_record: { unit_name: "Kg", status: "Active" } }
      post records_module_path("unit-master"), params: { module_record: { unit_name: "क्विंटल", status: "Active" } }
    end
    get module_path("unit-master")
    rows = css_select("#module_saved_records tbody tr").map { |tr| tr.text.squish }
    assert rows.any? { |row| row.include?("Kg") }
    assert rows.any? { |row| row.include?("क्विंटल") }

    assert_no_difference("ModuleRecord.where(module_slug: 'unit-master').count") do
      post records_module_path("unit-master"), params: { module_record: { unit_name: " kg ", status: "Active" } }
      post records_module_path("unit-master"), params: { module_record: { unit_name: "", status: "Active" } }
    end
  end
end
