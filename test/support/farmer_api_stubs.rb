# Stubs for the two outbound calls the farmer login makes: the ASA register
# and the SMS gateway. No test may reach either for real -- the gateway would
# text a live mobile number.
#
# Implemented with prepend plus an on/off flag rather than alias juggling.
# Aliasing had to be undone in an ensure block, and a stub that outlived its
# test went on reporting into the test that installed it, so a file that
# passed alone failed inside the full suite.
module FarmerApiStubs
  # Shared, not captured in a closure, so whichever stub is live writes where
  # the running test reads.
  SENT_OTPS = []
  REGISTER_CALLS = []

  class << self
    attr_accessor :active, :register_response, :register_error

    def reset!
      SENT_OTPS.clear
      REGISTER_CALLS.clear
      self.register_error = nil
      self.register_response = nil
    end

    def active?
      active.present?
    end
  end

  # Built fresh when needed rather than defined once, so the stub can be put
  # back at the front of the ancestor chain. Other suites
  # (otp_logins_controller_test, password_resets_controller_test) prepend
  # their own permanent OtpSmsSender module; whichever prepended last wins,
  # and when theirs won, no OTP ever reached this stub and the login tests
  # quietly asserted against an empty list.
  def self.register_lookup_module
    Module.new do
      def get(uri)
        return super unless FarmerApiStubs.active?

        FarmerApiStubs::REGISTER_CALLS << :attempt
        raise FarmerApiStubs.register_error if FarmerApiStubs.register_error

        FarmerApiStubs.register_response
      end
    end
  end

  def self.sms_sender_module
    Module.new do
      def deliver
        return super unless FarmerApiStubs.active?

        FarmerApiStubs::SENT_OTPS << otp
        OtpSmsSender::Result.new(success: true, message: "stubbed")
      end
    end
  end

  # Prepending a module that is already in the chain does not move it, so a
  # new one is built whenever something else has taken the front position.
  def self.ensure_front(klass, kind)
    @front ||= {}
    return if klass.ancestors.first.equal?(@front[[klass, kind]])

    mod = kind == :sms ? sms_sender_module : register_lookup_module
    klass.prepend(mod)
    @front[[klass, kind]] = mod
  end

  def self.http_ok(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { body }
    response
  end

  # Turns the stubs on for the duration of the block.
  #
  # Installed here rather than at load time: the stub has to be in front of
  # anything another suite has prepended since the last test ran.
  def stub_farmer_apis(farmer:, raising: nil)
    FarmerApiStubs.ensure_front(FarmerRegisterLookup, :register)
    FarmerApiStubs.ensure_front(OtpSmsSender, :sms)
    FarmerApiStubs.reset!
    FarmerApiStubs.register_response = FarmerApiStubs.http_ok(
      { "status" => true, "result" => farmer }.to_json
    )
    FarmerApiStubs.register_error = raising
    FarmerApiStubs.active = true

    yield FarmerApiStubs::SENT_OTPS, FarmerApiStubs::REGISTER_CALLS
  ensure
    FarmerApiStubs.active = false
  end
end

# The ASA location masters are plain id->name lookups. The override is
# installed for the whole test run so no test ever reaches the live master
# API: that would be slow, flaky, and traffic on the customer's server.
# Tests that care about names declare them with stub_names.
module AsaLocationNamesStub
  def self.names
    @names ||= Hash.new { |hash, key| hash[key] = {} }
  end

  def self.replace(values)
    @names = Hash.new { |hash, key| hash[key] = {} }
    values.each { |kind, pairs| @names[kind] = pairs.transform_keys(&:to_s) }
    @names
  end

  def lookup(kind, _path, _params, wanted_id)
    AsaLocationNamesStub.names[kind][wanted_id.to_s].presence
  end
end

AsaLocationNames.singleton_class.prepend(AsaLocationNamesStub)

class AsaLocationNames
  def self.stub_names(names = {})
    previous = AsaLocationNamesStub.names
    AsaLocationNamesStub.replace(names)
    yield
  ensure
    AsaLocationNamesStub.instance_variable_set(:@names, previous)
  end
end
