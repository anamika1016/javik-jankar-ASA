require "test_helper"

class JeevikaJankarToNameTest < ActiveSupport::TestCase
  def vrp(fcoc, to_name, tag)
    Vrp.create!(
      name: "TO JJ #{tag}", father_husband_name: "F", gender: :male,
      date_of_birth: Date.new(1990, 1, 1), date_of_joining: Date.current,
      aadhar_no: "123456789012", account_no: "1234567890", bank_name: "B",
      branch: "Br", ifsc_code: "TEST0123456", address: "A", mobile_no: "98765#{rand(10_000..99_999)}",
      email: "to#{tag}#{SecureRandom.hex(3)}@example.com", experience_in_years: 1,
      office_detail_id: 0, to_office_detail_id: 0, vrp_type_ids: [1],
      gram_panchayat_ids: [1], village_ids: [1], is_active: true,
      is_deleted: false, status: 55, password: "secret", fcoc: fcoc, to_name: to_name
    )
  end

  test "a row's TO is its Jeevika Jankar's own TO" do
    jj = vrp("FCO-Zeta#{SecureRandom.hex(2)}", "TO-Own", "a")
    assert_equal "TO-Own", JeevikaJankarToName.new.for(vrp_id: jj.id, fco: "anything")
  end

  test "without a known Jeevika Jankar the FCO's TO is used, whatever the FCO spelling" do
    place = "Qwerty#{SecureRandom.hex(2)}"
    vrp("FCO-#{place}", "TO-#{place}", "b")
    names = JeevikaJankarToName.new
    assert_equal "TO-#{place}", names.for(fco: "FCO-#{place}")
    assert_equal "TO-#{place}", names.for(fco: "#{place} - FCO")
    assert_equal "TO-#{place}", names.for(vrp_id: "", fco: place)
    assert_equal "-", names.for(vrp_id: "0", fco: "Nowhere#{SecureRandom.hex(2)}")
  end
end
