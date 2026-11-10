require "test_helper"

class FarmerAppLoginTest < ActiveSupport::TestCase
  # The register payload shape, taken from a live
  # farmer_details_by_identifier response.
  REGISTER_FARMER = {
    "id" => 5,
    "full_name" => "Pooja",
    "father_husband_name" => "Jay",
    "mobile_no" => "7898071513",
    "aadhaar_no" => "111122223333",
    "tracenet_id" => "MP2001415600",
    "ics_team_name" => "Ma Machna Crop Producer Company Ltd",
    "land_details" => [{ "id" => 2, "state_id" => 1, "district_id" => 36, "village_id" => 10143 }]
  }.freeze

  test "aadhaar is reduced to a digest and the last four digits, never stored whole" do
    digest = FarmerAppLogin.aadhaar_digest_for("1111 2222 3333")

    assert_equal digest, FarmerAppLogin.aadhaar_digest_for("111122223333")
    assert_not_equal digest, FarmerAppLogin.aadhaar_digest_for("111122223334")
    assert_not_includes digest, "111122223333"
    assert_nil FarmerAppLogin.aadhaar_digest_for("")
  end

  test "mobile numbers normalise to the last ten digits" do
    assert_equal "7898071513", FarmerAppLogin.normalize_mobile("+91 78980-71513")
    assert_equal "7898071513", FarmerAppLogin.normalize_mobile("917898071513")
  end

  test "repeat logins update one row and count up instead of inserting again" do
    first = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "aadhaar",
      aadhaar_no: "111122223333", ip: "10.0.0.1")
    second = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile",
      ip: "10.0.0.2")

    assert_equal first.id, second.id
    assert_equal 2, second.login_count
    assert_equal first.first_logged_in_at.to_i, second.first_logged_in_at.to_i
    assert_equal "Pooja", second.full_name
    assert_equal "3333", second.aadhaar_last4
    assert_equal "XXXX-XXXX-3333", second.masked_aadhaar
    assert_equal "******1513", second.masked_mobile
  end

  test "the OTP never travels inside the token it is verified against" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513",
      identifier_type: "aadhaar", aadhaar_no: "111122223333")

    assert_match(/\A\d{6}\z/, issued[:otp])
    assert_not_includes issued[:otp_token], issued[:otp]
    assert_not_includes issued[:otp_token], "111122223333"
  end

  test "a correct OTP verifies once and cannot be replayed" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")

    data = FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
    assert_equal "7898071513", data["mobile"]
    assert_equal :consumed, FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
  end

  test "wrong, tampered and expired OTPs are each refused" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")
    wrong = issued[:otp].succ.last(6)

    assert_equal :wrong_otp, FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: wrong)
    assert_equal :invalid_token, FarmerLoginOtp.verify(otp_token: "#{issued[:otp_token]}x", otp: issued[:otp])

    travel_to(FarmerLoginOtp::TTL.from_now + 1.minute) do
      assert_equal :expired, FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
    end
  end

  test "guessing is locked out after five wrong attempts on one token" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")
    FarmerLoginOtp::MAX_ATTEMPTS.times { FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: "000000") }

    assert_equal :too_many_attempts, FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
  end

  test "resend is throttled per mobile so an Aadhaar cannot be used to spam someone" do
    assert_not FarmerLoginOtp.resend_blocked?("7898071513")

    FarmerLoginOtp.note_sent("7898071513")
    assert FarmerLoginOtp.resend_blocked?("7898071513")
    assert_not FarmerLoginOtp.resend_blocked?("9000000000")
  end

  test "the register answer is held against the OTP so verify makes no second call" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513",
      identifier_type: "aadhaar", aadhaar_no: "111122223333")
    data = FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])

    held = FarmerLoginOtp.issued_farmer(data)
    assert_equal "Pooja", held["full_name"]
    # Held under the OTP, not the identifier, so an Aadhaar login reuses it too.
    assert_equal "7898071513", held["mobile_no"]
    assert_nil FarmerLoginOtp.issued_farmer("jti" => "expired-or-unknown")
  end

  test "repeat register lookups inside the cache window cost one outbound call" do
    Rails.cache.clear
    calls = []
    with_stubbed_register(calls, found_body) do
      assert_equal "Pooja", FarmerRegisterLookup.by_mobile("7898071513").farmer["full_name"]
      assert_equal "Pooja", FarmerRegisterLookup.by_mobile("7898071513").farmer["full_name"]
    end

    assert_equal 1, calls.size
  end

  test "an unreachable register is retried rather than cached as a failure" do
    Rails.cache.clear
    calls = []
    FarmerRegisterLookup.stub(:new, ->(**kwargs) {
      lookup = FarmerRegisterLookup.allocate
      lookup.send(:initialize, **kwargs)
      lookup.define_singleton_method(:get) { |_uri| calls << :attempt; raise Errno::ECONNREFUSED }
      lookup
    }) do
      2.times { assert_not FarmerRegisterLookup.by_mobile("7700000001").found? }
    end

    assert_equal 2, calls.size
  end

  test "an Aadhaar is never written into a cache key" do
    Rails.cache.clear
    with_stubbed_register([], found_body) { FarmerRegisterLookup.by_aadhaar("111122223333") }

    key = FarmerRegisterLookup.new(aadhaar_no: "111122223333").send(:cache_key)
    assert_not_includes key, "111122223333"
    assert Rails.cache.exist?(key), "the lookup should have been cached under the hashed key"
  end

  test "farmer tokens are not interchangeable with staff or Jeevika Jankar tokens" do
    login = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    farmer_token = FarmerApiToken.encode(login)

    assert_equal login.id, FarmerApiToken.find_login(farmer_token).id
    assert_nil ApiAuthToken.find_user(farmer_token)
    assert_nil ApiAuthToken.decode(farmer_token)
  end

  private

  def found_body
    { "status" => true, "result" => REGISTER_FARMER }.to_json
  end

  # Replaces only the HTTP call, so the caching and parsing under test is real.
  def with_stubbed_register(calls, body, &block)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { body }

    FarmerRegisterLookup.stub(:new, ->(**kwargs) {
      lookup = FarmerRegisterLookup.allocate
      lookup.send(:initialize, **kwargs)
      lookup.define_singleton_method(:get) { |_uri| calls << :attempt; response }
      lookup
    }, &block)
  end
end
