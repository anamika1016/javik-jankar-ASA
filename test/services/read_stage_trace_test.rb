require "test_helper"
require "stringio"

class ReadStageTraceTest < ActiveSupport::TestCase
  test "slow tracing preserves identity and logs only stage counts and timings" do
    previous = Rails.logger
    output = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(output)
    result = { "private_data" => "must-not-be-logged" }
    assert_same result, ReadStageTrace.measure("test.read", threshold_ms: Float::MIN) { result }
    assert_includes output.string, "PERFORMANCE_STAGE stage=test.read"
    assert_includes output.string, "items=1"
    refute_includes output.string, "private_data"
    refute_includes output.string, "must-not-be-logged"
    text = "sensitive-string"
    assert_same text, ReadStageTrace.measure("test.text", threshold_ms: Float::MIN) { text }
    assert_includes output.string, "bytes=#{text.bytesize}"
    refute_includes output.string, text
  ensure
    Rails.logger = previous
  end

  test "optional logger failure preserves read result and original exception" do
    previous = Rails.logger
    Rails.logger = Object.new.tap { |logger| def logger.info(*) = raise(IOError, "Unavailable") }
    result = []
    assert_same result, ReadStageTrace.measure("test.read", threshold_ms: Float::MIN) { result }
    error = RuntimeError.new("Original read failure")
    actual = assert_raises(RuntimeError) { ReadStageTrace.measure("test.read", threshold_ms: Float::MIN) { raise error } }
    assert_same error, actual
  ensure
    Rails.logger = previous
  end
end
