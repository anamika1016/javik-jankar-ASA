require "test_helper"

# ICS Wise target mapping builds its farmer list from AFL rows. The dialog shows
# "Village | Father | Tracenet", so every row must carry a village name.
class TargetMappingIcsVillageTest < ActiveSupport::TestCase
  setup do
    @controller = TargetMappingsController.new
    # These helpers reach for the request session, which a bare instance lacks.
    def @controller.admin_login?; true; end
    def @controller.current_app_user; { "username" => "tester", "user_type" => "admin" }; end
    def @controller.non_admin_vrp_login?; false; end
    @vrp = Vrp.create!(
      name: "ICS JJ", father_husband_name: "Father", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "Bank",
      branch: "Branch", ifsc_code: "TEST0123456", address: "Addr",
      mobile_no: "9876543210", email: "ics#{SecureRandom.hex(4)}@example.com",
      experience_in_years: 1, office_detail_id: 0, to_office_detail_id: 0,
      vrp_type_ids: [1], gram_panchayat_ids: [1], village_ids: [1],
      is_active: true, is_deleted: false, status: 10, password: "secret"
    )
  end

  def create_afl(village_name:, village_id: "116")
    Afl.create!(fco_id: "1009", fco: "Bhabra", ics_id: "18", ics_name: "BADGAON",
                village_id: village_id, village_name: village_name,
                farmer_name: "Pitabasa Bag", father_name: "Pitabasa Bag",
                tracenet_no: "OR2615009602")
  end

  def farmers_for
    @controller.send(:target_farmers_for,
      vrp_id: @vrp.id, fco_id: "1009||Bhabra", ics_id: "18||BADGAON",
      village_id: ["116||Badgaon"], month_name: "September",
      main_activity_name: "Farmers' Training", activity_name: "Sub")
  end

  test "the AFL village name reaches the farmer row" do
    create_afl(village_name: "Badgaon Village")

    row = farmers_for.first
    assert row, "expected a farmer row for the selected village"
    assert_equal "Badgaon Village", row[:village_name]
  end

  test "a blank AFL village falls back to the selected village label" do
    create_afl(village_name: nil)

    row = farmers_for.first
    assert row, "expected a farmer row for the selected village"
    assert_equal "Badgaon", row[:village_name],
      "a farmer with no AFL village should show the selected village"
  end

  # With neither an AFL village nor a labelled selection there is nothing to
  # show, but the key must still exist so the dialog renders "Village: -".
  test "the row never leaves village_name missing" do
    create_afl(village_name: nil)

    row = @controller.send(:target_farmers_for,
      vrp_id: @vrp.id, fco_id: "1009||Bhabra", ics_id: "18||BADGAON",
      village_id: ["116"], month_name: "September",
      main_activity_name: "Farmers' Training", activity_name: "Sub").first

    assert row, "expected a farmer row for the selected village"
    assert row.key?(:village_name), "village_name must always be present"
    assert_equal "-", row[:village_name]
  end
end
