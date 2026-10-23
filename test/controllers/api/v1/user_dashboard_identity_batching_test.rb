require "test_helper"

# The user dashboard decides which Jeevika Jankars are approved and which are
# still pending, and both answers depend on who registered each record. That
# creator was looked up one record at a time - by id, by email and by mobile
# number - so a dashboard holding ninety records spent around 280 queries
# before it could render. These tests pin the payload and the shape of the
# query load so the lookups stay batched.
class Api::V1::UserDashboardIdentityBatchingTest < ActionDispatch::IntegrationTest
  def admin_token
    user = User.create!(
      first_name: "Dash", last_name: "Admin", user_name: "dash_admin_batch",
      email: "dash_admin_batch@example.com", mobile_no: "9000000001",
      password: "secret", user_type: "admin", status: "Active"
    )
    ApiAuthToken.encode(user)
  end

  def create_jeevika_jankar(index)
    creator = User.create!(
      first_name: "Creator", last_name: index.to_s, user_name: "creator_#{index}",
      email: "creator_#{index}@example.com", mobile_no: "95000000#{format('%02d', index)}",
      password: "secret", user_type: "user", status: "Active"
    )
    Vrp.create!(
      name: "Batch JJ #{index}", father_husband_name: "Test", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "12345678#{format('%04d', index)}", account_no: "123456789#{index}",
      bank_name: "Test Bank", branch: "Test", ifsc_code: "TEST0123456",
      address: "Test", mobile_no: "98700000#{format('%02d', index)}",
      email: "batch_jj_#{index}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      user_name: "batch_jj_#{index}", password: "secret",
      created_by_type: "User", created_by_id: creator.id,
      # Status 55 (final approved) and anything below 25 short-circuit before
      # the approval steps are consulted, which is what asks who registered the
      # record. An in-flight approval status is what exercises those lookups.
      status: 30
    )
  end

  def user_table_query_count(token)
    count = 0
    callback = ->(*args) do
      sql = args.last[:sql].to_s
      count += 1 if sql.match?(/SELECT.*FROM "users"/m)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/api/v1/user-dashboard", headers: { "Authorization" => "Bearer #{token}" }, as: :json
    end
    assert_response :success
    count
  end

  test "user dashboard reports every visible Jeevika Jankar as registered and approved" do
    token = admin_token
    3.times { |index| create_jeevika_jankar(index) }

    get "/api/v1/user-dashboard", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    cards = response.parsed_body["cards"]
    assert_equal 3, cards["total_registered_vrp"]
    # No approval master is configured here, so no record counts as approved;
    # the point is that every visible record is still reported and counted.
    assert_equal 0, cards["final_approved_vrp"]
    assert_equal "user", response.parsed_body["dashboard_type"]
  end

  test "creator lookups do not grow one-per-record as the dashboard fills" do
    token = admin_token

    3.times { |index| create_jeevika_jankar(index) }
    small = user_table_query_count(token)

    (3...15).each { |index| create_jeevika_jankar(index) }
    large = user_table_query_count(token)

    # Twelve further records must not drag twelve more rounds of creator
    # lookups behind them. Before batching this grew by roughly three queries
    # per record; the batched form adds at most a handful of extra statements.
    assert_operator large, :<=, small + 6,
      "users-table queries grew from #{small} to #{large} after adding 12 records, " \
      "which means the creator lookups are running per record again"
  end

  test "records that answer from status alone are not batched for nothing" do
    token = admin_token
    baseline = user_table_query_count(token)

    # Status 55 short-circuits before any approval step is consulted, so these
    # must not pull creator lookups in behind them.
    6.times do |index|
      create_jeevika_jankar(index).update_columns(status: 55)
    end
    approved_only = user_table_query_count(token)

    assert_equal baseline, approved_only,
      "final-approved records added #{approved_only - baseline} creator lookups, " \
      "but their status answers the question without one"
  end
end
