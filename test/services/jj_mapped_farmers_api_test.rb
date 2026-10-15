require "test_helper"

# The scoping and row shaping behind the Jeevika Jankar Mapped Farmers screen.
# The two external lookups are injected, so no test reaches the upstream server.
class JjMappedFarmersApiTest < ActiveSupport::TestCase
  test "an admin is offered every Jeevika Jankar in the directory" do
    api = build(user_type: "admin")

    assert_equal "admin", api.login_type
    assert_equal %w[9000000001 9000000002], api.jeevika_jankar_options.map { |row| row[:mobile_no] }.sort
  end

  test "an admin reads the mapped farmers of whoever they picked" do
    result = build(user_type: "admin").mapped_farmers(mobile_no: "9000000001", month: "10", year: "2026")

    assert_equal "9000000001", result.dig(:filters, :mobile_no)
    assert_equal "Sangeeta Uikey", result.dig(:filters, :jeevika_jankar_name)
    assert_equal 2, result[:count]
    assert_equal ["Khairi", "Palaspani"], result[:mapped_villages].map { |v| v[:name] }.sort
  end

  test "an admin who picked nobody gets nobody's farmers" do
    result = build(user_type: "admin").mapped_farmers(month: "10", year: "2026")

    assert_nil result.dig(:filters, :mobile_no)
    assert_equal 0, result[:count]
    assert_empty result[:farmers]
  end

  # The point of the Jeevika Jankar login: nothing to choose, nobody else.
  test "a Jeevika Jankar login is locked to its own number" do
    api = build(record_type: "Vrp", mobile_no: "9000000001", name: "Sangeeta Uikey")

    assert_equal "jeevika_jankar", api.login_type
    assert_empty api.jeevika_jankar_options
    assert_equal "9000000001", api.resolve_mobile_no(nil)
  end

  test "a Jeevika Jankar asking for someone else is still given their own" do
    api = build(record_type: "Vrp", mobile_no: "9000000001", name: "Sangeeta Uikey")
    result = api.mapped_farmers(mobile_no: "9000000002", month: "10", year: "2026")

    assert_equal "9000000001", result.dig(:filters, :mobile_no)
    assert_equal 2, result[:count]
  end

  test "a cluster incharge is offered only the Jeevika Jankars mapped to them" do
    mine
    theirs
    api = build(record_type: "User", role: "Cluster Incharge", name: "Arti Shrama")

    assert_equal "staff", api.login_type
    assert_equal ["9000000001"], api.jeevika_jankar_options.map { |row| row[:mobile_no] }
  end

  test "a lone Jeevika Jankar is loaded without being chosen" do
    mine
    theirs
    api = build(record_type: "User", role: "Cluster Incharge", name: "Arti Shrama")

    assert_equal "9000000001", api.resolve_mobile_no(nil)
  end

  test "two Jeevika Jankars means the staff login has to choose" do
    mine
    vrp("Second JJ", "9000000003", cluster_incharge: "Arti Shrama")
    api = build(record_type: "User", role: "Cluster Incharge", name: "Arti Shrama")

    assert_nil api.resolve_mobile_no(nil), "with a real choice nothing may be picked for them"
  end

  test "a cluster incharge cannot reach a Jeevika Jankar outside their cluster" do
    mine
    theirs
    api = build(record_type: "User", role: "Cluster Incharge", name: "Arti Shrama")
    result = api.mapped_farmers(mobile_no: "9000000002", month: "10", year: "2026")

    assert_nil result.dig(:filters, :mobile_no)
    assert_equal 0, result[:count]
  end

  test "a staff login scoped by office sees that office's Jeevika Jankars" do
    vrp("Office JJ", "9000000004", fcoc: "FCO-C Sausar")
    vrp("Elsewhere JJ", "9000000005", fcoc: "FCO-C Turekela")
    api = build(record_type: "User", role: "Agronomist", name: "Office Staff", office_name: "FCO-Sausar")

    assert_equal ["9000000004"], api.jeevika_jankar_options.map { |row| row[:mobile_no] }
  end

  test "the village filter narrows the rows but keeps the total" do
    result = build(user_type: "admin")
      .mapped_farmers(mobile_no: "9000000001", month: "10", year: "2026", village_id: "3155")

    assert_equal 1, result[:count]
    assert_equal "Khairi", result[:farmers].first[:village_name]
    assert_equal 2, result[:total_count]
  end

  test "a village can be filtered by name as well as by id" do
    result = build(user_type: "admin")
      .mapped_farmers(mobile_no: "9000000001", month: "10", year: "2026", village_id: "palaspani")

    assert_equal 1, result[:count]
    assert_equal "Palaspani", result[:farmers].first[:village_name]
  end

  test "month and year fall back to today" do
    result = build(user_type: "admin").mapped_farmers(mobile_no: "9000000001")

    assert_equal Time.current.month.to_s, result.dig(:filters, :month)
    assert_equal Time.current.year.to_s, result.dig(:filters, :year)
  end

  test "a farmer row carries the columns the web report shows" do
    result = build(user_type: "admin").mapped_farmers(mobile_no: "9000000001", month: "10", year: "2026")
    row = result[:farmers].find { |farmer| farmer[:village_name] == "Khairi" }

    assert_equal 1, row[:sl_no]
    assert_equal "TN-001", row[:farmer_unique_id]
    assert_equal "Ramesh Patel", row[:farmer_name]
    assert_equal "Suresh Patel", row[:father_husband_name]
    assert_equal "Athner", row[:block_name]
    assert_equal "12, 13", row[:khasra_no]
    assert_equal 2.5, row[:land_area]
    assert_equal "Soybean", row[:crop_names], "the same crop on two plots is listed once"
    assert_equal "Approved", row[:status]
  end

  # A missing value has to read as a dash, not as blank or null.
  test "a row with nothing recorded reads as dashes" do
    result = build(user_type: "admin").mapped_farmers(mobile_no: "9000000002", month: "10", year: "2026")
    row = result[:farmers].first

    assert_equal "-", row[:farmer_name]
    assert_equal "-", row[:khasra_no]
    assert_equal "-", row[:land_area]
    assert_equal "-", row[:fco_name]
    assert_equal "Pending", row[:status]
  end

  test "the filters list the months and years the screen offers" do
    filters = build(user_type: "admin").filters

    assert_equal 12, filters[:months].size
    assert_equal({ id: "1", name: "January", label: "January (01)" }, filters[:months].first)
    assert_equal "2024", filters[:years].first
    assert_equal "2030", filters[:years].last
  end

  DIRECTORY = [
    { id: "1", name: "Sangeeta Uikey", mobile_no: "9000000001", label: "Sangeeta Uikey (9000000001)" },
    { id: "2", name: "Nilesh Nagwanshi", mobile_no: "9000000002", label: "Nilesh Nagwanshi (9000000002)" }
  ].freeze

  EXTERNAL_ROWS = {
    "9000000001" => [
      { "farmer" => { "farmer_unique_id" => "TN-001", "farmer_name" => "Ramesh Patel",
                      "father_husband_name" => "Suresh Patel", "mobile_no" => "9111111111",
                      "gender" => "Male" },
        "family" => { "social_category" => "ST", "user" => "sangeeta" },
        "address" => { "block" => "Athner", "district" => "Betul", "gram_panchayat" => "Khairi GP" },
        "grouping" => { "village" => "Khairi", "village_id" => "3155" },
        "lands" => [{ "khasra_no" => "12", "total_area" => 1.5, "crops" => [{ "crop_name" => "Soybean" }] },
                    { "khasra_no" => "13", "total_area" => 1.0, "crops" => [{ "crop_name" => "Soybean" }] }],
        "status" => "Approved" },
      { "farmer" => { "farmer_unique_id" => "TN-002", "farmer_name" => "Sita Bai" },
        "grouping" => { "village" => "Palaspani", "village_id" => "3178" }, "lands" => [] }
    ],
    "9000000002" => [{ "grouping" => { "village" => "Bothi", "village_id" => "3114" } }]
  }.freeze

  def build(**payload)
    JjMappedFarmersApi.new(current_app_user: payload.stringify_keys,
      vrp_directory: -> { DIRECTORY }, farmer_source: farmer_source)
  end

  # Shapes the stand-in rows through the same row mapping the real fetch uses,
  # so the payload under test is the payload the upstream server would produce.
  def farmer_source
    shaper = JjMappedFarmersApi.new(current_app_user: {})
    lambda do |mobile_no:, month:, year:|
      rows = EXTERNAL_ROWS.fetch(mobile_no.to_s, [])
      { farmers: rows.each_with_index.map { |row, index| shaper.send(:farmer_row, row, index) },
        mapped_villages: shaper.send(:village_rows, rows), count: rows.size }
    end
  end

  def mine
    @mine ||= vrp("Sangeeta Uikey", "9000000001", cluster_incharge: "Arti Shrama")
  end

  def theirs
    @theirs ||= vrp("Nilesh Nagwanshi", "9000000002", cluster_incharge: "Other CC")
  end

  def vrp(name, mobile, **extra)
    Vrp.create!({ name: name, father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: mobile,
      email: "jm#{SecureRandom.hex(4)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true, is_deleted: false,
      status: 55, user_name: "jm_#{SecureRandom.hex(4)}", password: "secret" }.merge(extra))
  end
end
