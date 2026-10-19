require "test_helper"

class Api::V1::JeevikaJankarBillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      first_name: "Bill", last_name: "Admin", user_name: "api_bill_admin",
      email: "api_bill_admin@example.com", mobile_no: "9876512345", password: "secret",
      user_type: "admin", status: "Active", stakeholder: "PAPL", role: "Admin"
    )
    post api_v1_login_path, params: { login: @admin.user_name, password: "secret" }, as: :json
    @headers = { "Authorization" => "Bearer #{response.parsed_body['token']}" }
  end

  test "bill list supports VRP project and project fields without error" do
    vrp = create_vrp(name: "Bill JJ", user_name: "bill_jj", created_by_id: @admin.id)
    bill = ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
      "select_vrp" => vrp.id.to_s,
      "select_vrp_name" => "Bill JJ",
      "financial_year" => "2026-27",
      "bill_month" => "October",
      "vrp_project" => ["VRP Project One"],
      "project" => ["Project Two"],
      "project_master_ids" => %w[11 12],
      "bill_details" => [],
      "status" => "Submitted"
    })

    get "/api/v1/jeevika-jankar-bills", headers: @headers, as: :json

    assert_response :success
    row = response.parsed_body["bills"].find { |item| item["id"] == bill.id }
    assert row
    assert_equal "October", row["bill_month"]
  end

  test "bill list query count stays bounded as bill count grows" do
    vrp = create_vrp(name: "Fast Bill JJ", user_name: "fast_bill_jj", created_by_id: @admin.id)
    20.times do |index|
      ModuleRecord.create!(module_slug: "jeevika-jankar-bill-process", data: {
        "select_vrp" => vrp.id.to_s,
        "select_vrp_name" => "Fast Bill JJ",
        "financial_year" => "2026-27",
        "bill_month" => "October",
        "bill_items" => [{ "main_activity" => "Activity", "activity" => "Work" }],
        "status" => "Submitted #{index}"
      })
    end

    select_count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      select_count += 1 if payload[:sql].to_s.match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/api/v1/jeevika-jankar-bills", headers: @headers, as: :json
    end

    assert_response :success
    assert_operator select_count, :<=, 25
    assert_equal 20, response.parsed_body["count"]
  end

  private

  def create_vrp(attributes = {})
    defaults = {
      name: "Test JJ", father_husband_name: "Father", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "Bank",
      branch: "Branch", ifsc_code: "TEST0123456", address: "Address",
      mobile_no: "9876543210", email: "bill_jj@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 10, password: "secret"
    }
    Vrp.create!(defaults.merge(attributes))
  end
end
