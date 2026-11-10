require "test_helper"
require_relative "../support/farmer_api_stubs"

class FarmerAppLoginTest < ActiveSupport::TestCase
  include FarmerApiStubs

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

  test "only ten-digit Indian mobile numbers are accepted" do
    %w[6123456789 7898071513 8000000000 9999999999].each do |number|
      assert FarmerAppLogin.valid_mobile?(number), "#{number} should be valid"
    end

    # Accepted spellings of a valid number: country code and trunk zero only.
    ["+91 78980-71513", "07898071513", "917898071513", "0091 7898071513"].each do |number|
      assert FarmerAppLogin.valid_mobile?(number), "#{number} should be valid"
    end

    [
      "5898071513",     # starts with 5
      "1234567890",     # starts with 1
      "0898071513",     # ten digits starting with 0
      "789807151",      # nine digits
      "78980715130",    # eleven digits, no trunk zero
      "99997898071513", # junk in front of a real number
      "789807151a",     # letters stripped, leaves nine digits
      "0000000000",
      "",
      nil
    ].each do |number|
      assert_not FarmerAppLogin.valid_mobile?(number), "#{number.inspect} should be rejected"
    end
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

  test "every sign-in is kept as its own event, not just the latest" do
    travel_to(3.days.ago) do
      FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile", ip: "10.0.0.1")
    end
    login = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "aadhaar",
      aadhaar_no: "111122223333", ip: "10.0.0.2")

    assert_equal 1, FarmerAppLogin.count
    assert_equal 2, login.login_events.count
    # The summary row holds the latest; the events hold the history.
    assert_equal "aadhaar", login.last_identifier_type
    assert_equal ["mobile", "aadhaar"], login.login_events.order(:logged_in_at).pluck(:identifier_type)
    assert_equal 1, FarmerAppLoginEvent.on_date(3.days.ago.to_date).count
    assert_equal 1, FarmerAppLoginEvent.on_date(Date.current).count
  end

  test "a different register id is a different farmer even on a repeated Aadhaar" do
    first = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "aadhaar",
      aadhaar_no: "111122223333")
    second = FarmerAppLogin.record_login!(
      farmer: REGISTER_FARMER.merge("id" => 9, "full_name" => "Ramesh"),
      identifier_type: "aadhaar", aadhaar_no: "111122223333"
    )

    assert_not_equal first.id, second.id
    assert_equal "Pooja", first.reload.full_name, "the first farmer's row must not be overwritten"
    assert_equal "Ramesh", second.full_name
  end

  test "the OTP never travels inside the token it is verified against" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513",
      identifier_type: "aadhaar", aadhaar_no: "111122223333")

    assert_match(/\A\d{6}\z/, issued[:otp])
    assert_not_includes issued[:otp_token], issued[:otp]
    assert_not_includes issued[:otp_token], "111122223333"
  end

  # Replay protection must hold with no cache at all -- this environment runs
  # :null_store, which is exactly the condition that broke it before.
  test "a correct OTP verifies once and cannot be replayed" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")

    request = FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
    assert_equal "7898071513", request.mobile_no
    assert_equal :consumed, FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
  end

  test "the OTP is stored only as a digest, never in readable form" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513",
      identifier_type: "aadhaar", aadhaar_no: "111122223333")
    row = FarmerLoginOtpRequest.order(:id).last

    assert_not_equal issued[:otp], row.otp_digest
    assert_not_includes row.attributes.values.map(&:to_s), issued[:otp]
    # The register payload carries an Aadhaar, so it must not be on the row.
    assert_not_includes FarmerLoginOtpRequest.column_names, "farmer_payload"
    assert_not_includes row.attributes.values.map(&:to_s), "111122223333"
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

  test "wrong guesses are counted on the row so the web list can report them" do
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")
    3.times { FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: "000000") }

    row = FarmerLoginOtpRequest.find_by(mobile_no: "7898071513")
    assert_equal 3, row.attempts
    # The cap itself lives on the mobile number, not on this row, so a correct
    # OTP still works -- it is FarmerLoginLock that bars a locked number.
    assert_instance_of FarmerLoginOtpRequest,
      FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])
  end

  test "the lock counts wrong guesses per mobile and releases after an hour" do
    3.times { FarmerLoginLock.register_failure!("7898071513") }
    assert_nil FarmerLoginLock.active_lock("7898071513"), "three wrong tries are still allowed"
    assert_equal 0, FarmerLoginLock.for_mobile("7898071513").attempts_left

    lock = FarmerLoginLock.register_failure!("7898071513")
    assert lock.locked?
    assert_equal 60, lock.minutes_remaining
    assert FarmerLoginLock.active_lock("7898071513")

    travel_to(FarmerLoginLock::LOCK_DURATION.from_now + 1.minute) do
      assert_nil FarmerLoginLock.active_lock("7898071513")
      assert_equal 0, FarmerLoginLock.for_mobile("7898071513").failed_attempts
    end
  end

  test "a new OTP retires the previous one for the same mobile" do
    first = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")
    second = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")

    assert_equal :expired, FarmerLoginOtp.verify(otp_token: first[:otp_token], otp: first[:otp])
    assert_instance_of FarmerLoginOtpRequest,
      FarmerLoginOtp.verify(otp_token: second[:otp_token], otp: second[:otp])
  end

  test "resend is throttled per mobile so an Aadhaar cannot be used to spam someone" do
    assert_not FarmerLoginOtp.resend_blocked?("7898071513")

    FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")
    assert FarmerLoginOtp.resend_blocked?("7898071513")
    assert_not FarmerLoginOtp.resend_blocked?("9000000000")

    travel_to(FarmerLoginOtp::RESEND_INTERVAL.from_now + 1.second) do
      assert_not FarmerLoginOtp.resend_blocked?("7898071513")
    end
  end

  test "the register answer is held against the OTP so verify makes no second call" do
    with_memory_cache do
      issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513",
        identifier_type: "aadhaar", aadhaar_no: "111122223333")
      request = FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])

      held = FarmerLoginOtp.issued_farmer(request)
      assert_equal "Pooja", held["full_name"]
      # Held under the OTP, not the identifier, so an Aadhaar login reuses it too.
      assert_equal "7898071513", held["mobile_no"]
    end
  end

  test "losing the held payload costs a lookup but never a failed login" do
    # :null_store here, so nothing is ever held -- the login must still work.
    issued = FarmerLoginOtp.issue(farmer: REGISTER_FARMER, mobile: "7898071513", identifier_type: "mobile")
    request = FarmerLoginOtp.verify(otp_token: issued[:otp_token], otp: issued[:otp])

    assert_instance_of FarmerLoginOtpRequest, request
    assert_nil FarmerLoginOtp.issued_farmer(request)
  end

  test "repeat register lookups inside the cache window cost one outbound call" do
    with_memory_cache do
      calls = []
      with_stubbed_register(calls) do
        assert_equal "Pooja", FarmerRegisterLookup.by_mobile("7898071513").farmer["full_name"]
        assert_equal "Pooja", FarmerRegisterLookup.by_mobile("7898071513").farmer["full_name"]
      end

      assert_equal 1, calls.size
    end
  end

  test "an unreachable register is retried rather than cached as a failure" do
    with_memory_cache do
      calls = []
      with_stubbed_register(calls, raising: Errno::ECONNREFUSED) do
        2.times { assert_not FarmerRegisterLookup.by_mobile("7700000001").found? }
      end

      assert_equal 2, calls.size
    end
  end

  test "an Aadhaar is never written into a cache key" do
    with_memory_cache do
      with_stubbed_register([]) { FarmerRegisterLookup.by_aadhaar("111122223333") }

      key = FarmerRegisterLookup.new(aadhaar_no: "111122223333").send(:cache_key)
      assert_not_includes key, "111122223333"
      assert Rails.cache.exist?(key), "the lookup should have been cached under the hashed key"
    end
  end

  test "farmer tokens are not interchangeable with staff or Jeevika Jankar tokens" do
    login = FarmerAppLogin.record_login!(farmer: REGISTER_FARMER, identifier_type: "mobile")
    farmer_token = FarmerApiToken.encode(login)

    assert_equal login.id, FarmerApiToken.find_login(farmer_token).id
    assert_nil ApiAuthToken.find_user(farmer_token)
    assert_nil ApiAuthToken.decode(farmer_token)
  end

  private

  # This environment runs :null_store. Swap in a real store for the cases that
  # are specifically about caching behaviour.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield Rails.cache
  ensure
    Rails.cache = original
  end

  # Replaces only the HTTP call, so the caching and parsing under test is the
  # real thing.
  def with_stubbed_register(calls, raising: nil)
    stub_farmer_apis(farmer: REGISTER_FARMER, raising: raising) do |_sent, register_calls|
      yield
      calls.concat(register_calls)
    end
  end
end
