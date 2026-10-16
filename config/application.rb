require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module VrpApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Kolkata"

    # The app downloads long option lists - the location hierarchy alone runs to
    # hundreds of kilobytes - and JSON of that shape compresses by roughly ten
    # times. Limited to /api so the website is served exactly as it is today.
    config.middleware.use Rack::Deflater,
      if: ->(env, _status, _headers, _body) { env["PATH_INFO"].to_s.start_with?("/api/") }
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
