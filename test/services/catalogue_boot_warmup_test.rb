require "test_helper"

class CatalogueBootWarmupTest < ActiveSupport::TestCase
  test "only enabled production cluster warmup executes the loader" do
    calls = 0
    refute CatalogueBootWarmup.run(environment: "test", enabled: "1") { calls += 1 }
    refute CatalogueBootWarmup.run(environment: "production", enabled: "0") { calls += 1 }
    assert CatalogueBootWarmup.run(environment: "production", enabled: "1") { calls += 1 }
    assert_equal 1, calls
    refute CatalogueBootWarmup.run(environment: "production", enabled: "1") { raise IOError, "optional warmup failed" }
  end

  test "Puma cluster registers prewarm before forking and single mode does not" do
    previous = ENV.to_h.slice("RAILS_ENV", "WEB_CONCURRENCY", "RAILS_MAX_THREADS", "SOLID_QUEUE_IN_PUMA")
    ENV["RAILS_ENV"] = "production"
    ENV["WEB_CONCURRENCY"] = "2"
    configuration = Class.new do
      attr_reader :hooks
      def initialize; @hooks = []; end
      def before_fork(&block); @hooks << block; end
      def method_missing(*); nil; end
      def respond_to_missing?(*); true; end
    end
    cluster = configuration.new
    cluster.instance_eval(File.read(Rails.root.join("config/puma.rb")))
    assert_equal 1, cluster.hooks.size
    original = CatalogueBootWarmup.method(:run)
    called = 0
    CatalogueBootWarmup.define_singleton_method(:run) { called += 1 }
    cluster.hooks.first.call
    assert_equal 1, called
    ENV["WEB_CONCURRENCY"] = "0"
    single = configuration.new
    single.instance_eval(File.read(Rails.root.join("config/puma.rb")))
    assert_empty single.hooks
  ensure
    CatalogueBootWarmup.define_singleton_method(:run, original) if original
    %w[RAILS_ENV WEB_CONCURRENCY RAILS_MAX_THREADS SOLID_QUEUE_IN_PUMA].each do |name|
      previous&.key?(name) ? ENV[name] = previous[name] : ENV.delete(name)
    end
  end
end
