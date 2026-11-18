require "test_helper"

# Lists that already show the FCO also show the TO, right after it.
class FcoListsToNameTest < ActionDispatch::IntegrationTest
  setup do
    @tag = SecureRandom.hex(4)
    @vrp = Vrp.create!(
      name: "List JJ #{@tag}", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: "9876500077",
      email: "list#{@tag}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: "FCO-List#{@tag}", to_name: "TO-List#{@tag}"
    )
    admin = User.create!(user_name: "list_admin_#{@tag}", password: "secret", first_name: "Adm",
                         user_type: "admin", status: "Active")
    post login_path, params: { login: admin.user_name, password: "secret" }
  end

  def row_after(list_slug, fco_header)
    get module_path(list_slug)
    assert_response :success
    table = css_select("table").find { |t| t.text.include?("TO Name") }
    headers = table.css("thead th").map { |th| th.text.strip }
    at = headers.index(fco_header)
    assert_equal "TO Name", headers[at + 1]
    cells = table.css("tbody tr").find { |tr| tr.text.include?(@vrp.fcoc) }.css("td").map { |td| td.text.strip }
    assert_equal headers.size, cells.size
    [cells[at], cells[at + 1]]
  end

  test "training form list shows TO after FCO Name" do
    ModuleRecord.create!(module_slug: "training-form", data: {
      "month" => "October", "fco_name" => @vrp.fcoc, "jeevika_jankar_id" => @vrp.id.to_s,
      "trainer_name" => @vrp.name, "training_date" => "2026-10-10"
    })
    assert_equal [@vrp.fcoc, @vrp.to_name], row_after("training-form-list", "FCO Name")
  end

  test "other target lists show TO after Department" do
    %w[other-target other-target-with-farmer].each do |slug|
      ModuleRecord.create!(module_slug: slug, data: {
        "jeevika_jankar_name" => @vrp.name, "jeevika_jankar_id" => @vrp.id.to_s,
        "department" => @vrp.fcoc, "fcoc_name" => @vrp.fcoc, "month" => "October"
      })
      assert_equal [@vrp.fcoc, @vrp.to_name], row_after("#{slug}-list", "Department")
    end
  end
end
